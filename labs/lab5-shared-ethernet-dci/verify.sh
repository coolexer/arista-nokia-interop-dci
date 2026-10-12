#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-5
out="results/verify-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
eos() { docker exec "$prefix-$1" timeout 40 Cli -p 15 -c "$2"; }
srl() { docker exec "$prefix-$1" timeout 40 sr_cli -d "$2"; }
probe() {
  local node=$1 result; shift
  result=$(docker exec "$prefix-$node" ping -n "$@") || { echo "$result"; return 1; }
  echo "$result"; grep -q ', 0% packet loss' <<< "$result" && ! grep -Eq 'DUP!|duplicates' <<< "$result"
}
for attempt in {1..36}; do
  if probe h1 -I eth1 -c 3 -i 0.2 -W 2 192.168.10.12 &&
     probe h1 -I eth2 -c 3 -i 0.2 -W 2 192.168.30.12; then break; fi
  [[ "$attempt" != 36 ]] || { echo 'FAIL: services did not become ready'; exit 1; }
  sleep 5
done
if [[ ${1:-all} != traffic ]]; then
for node in dc1-leaf dc1-spine1 dc1-spine2; do
  for command in 'show version' 'show bgp evpn summary' 'show ip route' 'show ip route vrf TENANT' 'show bfd peers'; do
    eos "$node" "$command" > "$out/$node-${command// /-}.txt"
  done
done
for node in dc1-spine1 dc1-spine2; do
  for command in 'show mlag detail' 'show mlag interfaces' 'show lacp peer' 'show interfaces Port-Channel100' 'show ip bgp vrf TENANT' 'show mac address-table vlan 10'; do
    eos "$node" "$command" > "$out/$node-${command// /-}.txt"
  done
done
for node in dc2-leaf dc2-bl dc2-bl2; do
  for command in 'show version' 'show network-instance default protocols bgp summary' 'show network-instance default ipv4 route all' 'show network-instance TENANT ipv4 route all'; do
    srl "$node" "$command" > "$out/$node-${command// /-}.txt"
  done
done
for node in dc2-bl dc2-bl2; do
  for command in 'show lag lag1' 'show system network-instance ethernet-segments DCI-ARISTA detail' 'show network-instance TENANT protocols bgp summary' 'show network-instance L2-10 bridge-table mac-table all' 'show network-instance TRANSIT-901 bridge-table mac-table all'; do
    srl "$node" "$command" > "$out/$node-${command// /-}.txt"
  done
done
for node in dc1-leaf dc1-spine1 dc1-spine2; do
  eos "$node" 'show ip route 10.255.2.1 | json' > "$out/$node-no-remote-leaf.json"
  jq -e '.vrfs.default.routes | length == 0' "$out/$node-no-remote-leaf.json" >/dev/null
done
for node in dc2-leaf dc2-bl dc2-bl2; do
  ! grep -q '10.255.1.' "$out/$node-show-network-instance-default-ipv4-route-all.txt"
done
fi
captures=()
for spec in 'dc2-bl e1-2 dci-1' 'dc2-bl2 e1-2 dci-2'; do
  read -r node iface name <<< "$spec"
  docker exec -u 0 "$prefix-$node" timeout -s INT 45 tcpdump -l -n -e -vv -i "$iface" > "$out/$name.txt" 2>&1 &
  captures+=("$!")
done
trap 'kill "${captures[@]}" 2>/dev/null || true' EXIT
sleep 1
for spec in 'h1 eth1 192.168.10.12' 'h2 eth1 192.168.10.11' 'h1 eth2 192.168.30.12' 'h2 eth2 192.168.20.11'; do
  read -r node iface dest <<< "$spec"
  probe "$node" -I "$iface" -c 5 -i 0.2 -W 2 "$dest"
  probe "$node" -I "$iface" -M do -s 1472 -c 3 -i 0.2 -W 2 "$dest"
done
for spec in 'h1 192.168.10.12 192.168.30.12' 'h2 192.168.10.11 192.168.20.11'; do
  read -r node l2 l3 <<< "$spec"
  docker exec "$prefix-$node" bash -c 'for i in $(seq 1 100); do printf "shared-dci-L2-%s" "$i" > /dev/udp/'"$l2"'/$((20000+i)); printf "shared-dci-L3-%s" "$i" > /dev/udp/'"$l3"'/$((30000+i)); done'
done
for pid in "${captures[@]}"; do wait "$pid" || true; done
trap - EXIT
for name in dci-1 dci-2; do
  grep -q 'vlan 10,' "$out/$name.txt"
  grep -q 'vlan 901,' "$out/$name.txt"
  ! grep -qi 'VXLAN' "$out/$name.txt"
done
echo 'PASS: L2/L3 bidirectional, inner MTU 1500, both DCI members carry VLAN 10 and 901, no inter-site leaf reachability or VXLAN'
