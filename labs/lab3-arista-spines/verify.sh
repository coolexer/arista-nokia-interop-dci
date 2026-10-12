#!/usr/bin/env bash
# Verify the separately deployed Lab 3; no deploy/start/pull here.
set -euo pipefail
cd -- "$(dirname -- "$0")"
mode=${1:-all}
case "$mode" in all|l2|l3) ;; *) echo 'Usage: ./verify.sh [all|l2|l3]' >&2; exit 2 ;; esac
prefix=clab-interop-dci-3
for node in dc1-leaf dc1-spine1 dc1-spine2 dc2-bl dc2-bl2 dc2-leaf h1 h2; do
  [[ $(docker inspect -f '{{.State.Running}}' "$prefix-$node" 2>/dev/null) == true ]] || {
    echo "Lab node is not running: $prefix-$node. Deploy the lab separately." >&2; exit 1;
  }
done
out="results/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
srl() { docker exec "$prefix-$1" timeout 30 sr_cli -d "$2"; }
eos() { docker exec "$prefix-dc1-leaf" timeout 30 Cli -c "$1"; }
check_ping() {
  local node=$1 output
  shift
  output=$(docker exec "$prefix-$node" ping -n "$@") || { echo "$output"; return 1; }
  echo "$output"
  grep -q ', 0% packet loss' <<< "$output"
}
ping_host() { check_ping "$1" -I "$2" -i 0.2 -c 5 -W 2 "$3"; }
echo "Results: $out"
for node in dc2-bl dc2-bl2 dc2-leaf; do
  srl "$node" 'show version' | tee "$out/$node-version.txt"
  grep -q '26.7.1' "$out/$node-version.txt" || { echo "Wrong SR Linux release: $node"; exit 1; }
  srl "$node" 'show network-instance default protocols bgp summary' > "$out/$node-bgp.txt"
  srl "$node" 'show network-instance default ipv4 route all' > "$out/$node-underlay.txt"
done
for spine in dc1-spine1 dc1-spine2; do
  docker exec "$prefix-$spine" timeout 30 Cli -c 'show version' > "$out/$spine-version.txt"
  docker exec "$prefix-$spine" timeout 30 Cli -c 'show ip bgp summary' > "$out/$spine-bgp.txt"
  docker exec "$prefix-$spine" timeout 30 Cli -c 'show bfd peers' > "$out/$spine-bfd.txt"
  docker exec "$prefix-$spine" timeout 30 Cli -c 'show ip route' > "$out/$spine-routes.txt"
done
eos 'show ip route 10.255.2.1' > "$out/arista-vtep-ecmp.txt"
srl dc2-leaf 'show network-instance default ipv4 route 10.255.1.1/32' > "$out/nokia-vtep-ecmp.txt"
eos 'show version'  | tee "$out/dc1-leaf-version.txt"
grep -q '4.34.7M' "$out/dc1-leaf-version.txt" || { echo 'Wrong EOS release'; exit 1; }
eos 'show ip bgp summary' > "$out/dc1-leaf-underlay.txt"
eos 'show bgp evpn summary' > "$out/dc1-leaf-evpn.txt"
eos 'show bgp evpn route-type mac-ip' > "$out/dc1-leaf-rt2.txt"
eos 'show bgp evpn route-type imet' > "$out/dc1-leaf-rt3.txt"
eos 'show bgp evpn route-type ip-prefix ipv4' > "$out/dc1-leaf-rt5.txt"
for type in 2 3 5; do
  srl dc2-leaf "show network-instance default protocols bgp routes evpn route-type $type detail" > "$out/dc2-leaf-rt$type.txt"
done
srl dc2-leaf 'show network-instance TENANT ipv4 route all' > "$out/dc2-leaf-tenant.txt"
eos 'show ip route vrf TENANT' > "$out/dc1-leaf-tenant.txt"
if [[ "$mode" == all || "$mode" == l3 ]]; then
  grep -q '192.168.20.0/24' "$out/dc2-leaf-rt5.txt"
  grep -q '192.168.30.0/24' "$out/dc1-leaf-rt5.txt"
fi
# Capture both DCI circuits; service/ECMP selection may use either BL.
capture_pids=()
docker exec -u 0 "$prefix-dc2-bl" timeout 30 tcpdump -l -n -e -vv -i e1-2 \
  'udp port 4789' > "$out/dci-1.txt" 2>&1 &
capture_pids+=("$!")
docker exec -u 0 "$prefix-dc2-bl2" timeout 30 tcpdump -l -n -e -vv -i e1-2 \
  'udp port 4789' > "$out/dci-2.txt" 2>&1 &
capture_pids+=("$!")
trap 'kill "${capture_pids[@]}" 2>/dev/null || true' EXIT
sleep 1
if [[ "$mode" == all || "$mode" == l2 ]]; then
  docker exec "$prefix-h1" ip neigh flush dev eth1
  docker exec "$prefix-h2" ip neigh flush dev eth1
  ping_host h1 eth1 192.168.10.12
  ping_host h2 eth1 192.168.10.11
  check_ping h1 -I eth1 -i 0.2 -M do -s 1472 -c 3 -W 2 192.168.10.12
  check_ping h2 -I eth1 -i 0.2 -M do -s 1472 -c 3 -W 2 192.168.10.11
fi
if [[ "$mode" == all || "$mode" == l3 ]]; then
  ping_host h1 eth2 192.168.20.1
  ping_host h2 eth2 192.168.30.1
  ping_host h1 eth2 192.168.30.12
  ping_host h2 eth2 192.168.20.11
  check_ping h1 -I eth2 -i 0.2 -M do -s 1472 -c 3 -W 2 192.168.30.12
  check_ping h2 -I eth2 -i 0.2 -M do -s 1472 -c 3 -W 2 192.168.20.11
fi
for pid in "${capture_pids[@]}"; do wait "$pid" || true; done
trap - EXIT
cat "$out/dci-1.txt" "$out/dci-2.txt" > "$out/dci-vxlan.txt"
if [[ "$mode" == all || "$mode" == l2 ]]; then grep -qi "vni 10010" "$out/dci-vxlan.txt"; fi
if [[ "$mode" == all || "$mode" == l3 ]]; then grep -qi "vni 50000" "$out/dci-vxlan.txt"; fi
srl dc2-leaf 'show network-instance L2-10 bridge-table mac-table all' > "$out/dc2-leaf-macs.txt"
eos 'show mac address-table vlan 10' > "$out/dc1-leaf-macs.txt"
echo "PASS: $mode bidirectional connectivity, inner IP MTU 1500 and DCI VXLAN VNI capture."
echo 'Review RT-2/3/5, EVPN next-hops and the negative tests in README.md before accepting the design.'
