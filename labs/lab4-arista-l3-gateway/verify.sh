#!/usr/bin/env bash
# Functional RT-5 gateway check on cEOS, not a 7260CX3 ASIC qualification.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-4
out="results/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
eos() { docker exec "$prefix-$1" timeout 45 Cli -p 15 -c "$2"; }
srl() { docker exec "$prefix-$1" timeout 45 sr_cli -d "$2"; }
probe() {
  local output node=$1; shift
  output=$(docker exec "$prefix-$node" ping -n "$@") || { echo "$output"; return 1; }
  echo "$output"; grep -q ', 0% packet loss' <<< "$output"
}
for attempt in {1..24}; do
  if probe h1 -I eth2 -c 3 -i 0.2 -W 2 192.168.30.12 && probe h2 -I eth2 -c 3 -i 0.2 -W 2 192.168.20.11; then break; fi
  [[ "$attempt" != 24 ]] || { echo 'FAIL: L3 did not become ready'; exit 1; }
  sleep 5
done
for node in dc1-leaf dc1-spine1 dc1-spine2; do
  eos "$node" 'show version' > "$out/$node-version.txt"
  eos "$node" 'show bgp evpn summary' > "$out/$node-evpn.txt"
  eos "$node" 'show bgp evpn route-type ip-prefix ipv4 detail' > "$out/$node-rt5.txt"
  eos "$node" 'show ip route vrf TENANT' > "$out/$node-tenant.txt"
  eos "$node" 'show ip route' > "$out/$node-underlay.txt"
done
for node in dc2-leaf dc2-bl dc2-bl2; do
  srl "$node" 'show version' > "$out/$node-version.txt"
  srl "$node" 'show network-instance default protocols bgp summary' > "$out/$node-bgp.txt"
  srl "$node" 'show network-instance default ipv4 route all' > "$out/$node-underlay.txt"
done
srl dc2-leaf 'show network-instance TENANT ipv4 route all' > "$out/dc2-leaf-tenant.txt"
srl dc2-leaf 'show network-instance default protocols bgp routes evpn route-type 5 detail' > "$out/dc2-leaf-rt5.txt"
srl dc2-leaf 'show network-instance default protocols bgp routes evpn route-type 2 detail' > "$out/dc2-leaf-rt2.txt"
srl dc2-leaf 'show network-instance default protocols bgp routes evpn route-type 3 detail' > "$out/dc2-leaf-rt3.txt"
# Remote leaf VTEPs must not be reachable directly at either access leaf.
eos dc1-leaf 'show ip route 10.255.2.1 | json' > "$out/arista-no-remote-leaf.json"
jq -e '.vrfs.default.routes | length == 0' "$out/arista-no-remote-leaf.json" >/dev/null
! grep -q '10.255.1.1/32' "$out/dc2-leaf-underlay.txt"
grep -Eq 'via VTEP 10.255.1.(253|254)' "$out/dc1-leaf-tenant.txt"
grep -Eq '10.255.1.(253|254)\(tunnel:vxlan' "$out/dc2-leaf-tenant.txt"
captures=()
for spec in 'dc1-spine1 eth1 fabric-1' 'dc1-spine2 eth1 fabric-2' 'dc2-bl e1-2 dci-1' 'dc2-bl2 e1-2 dci-2'; do
  read -r node iface label <<< "$spec"
  docker exec -u 0 "$prefix-$node" timeout -s INT 20 tcpdump -l -n -e -vv -i "$iface" 'udp port 4789' > "$out/$label.txt" 2>&1 &
  captures+=("$!")
done
trap 'kill "${captures[@]}" 2>/dev/null || true' EXIT
sleep 1
probe h1 -I eth2 -c 5 -i 0.2 -W 2 192.168.30.12
probe h2 -I eth2 -c 5 -i 0.2 -W 2 192.168.20.11
probe h1 -I eth2 -M do -s 1472 -c 3 -i 0.2 -W 2 192.168.30.12
probe h2 -I eth2 -M do -s 1472 -c 3 -i 0.2 -W 2 192.168.20.11
for pid in "${captures[@]}"; do wait "$pid" || true; done
trap - EXIT
cat "$out/fabric-1.txt" "$out/fabric-2.txt" > "$out/fabric.txt"
cat "$out/dci-1.txt" "$out/dci-2.txt" > "$out/dci.txt"
grep -qi 'vni 50000' "$out/fabric.txt"
grep -qi 'vni 50000' "$out/dci.txt"
grep -Eq '10.255.1.(253|254)\.[0-9]+ > 10.255.2.1.4789|10.255.2.1\.[0-9]+ > 10.255.1.(253|254).4789' "$out/dci.txt"
! grep -Eq '10.255.1.1\.[0-9]+ > 10.255.2.1.4789|10.255.2.1\.[0-9]+ > 10.255.1.1.4789' "$out/dci.txt"
docker exec "$prefix-h1" ip neigh flush dev eth1
if docker exec "$prefix-h1" ping -n -I eth1 -c 3 -W 1 192.168.10.12; then echo 'FAIL: unexpected L2 stretch'; exit 1; fi
echo 'PASS: bidirectional L3/MTU, gateway next hops and separate VXLAN legs; no remote-leaf reachability or L2 stretch'
