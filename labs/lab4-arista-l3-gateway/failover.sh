#!/usr/bin/env bash
# L3 gateway endpoint and DCI-link failures. Always restore pending faults.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-4
out="results/failover-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
paused=''; port_node=''
port() {
  local node=$1 command=$2 commands
  printf -v commands 'configure terminal\ninterface Ethernet2\n%s' "$command"
  docker exec "$prefix-$node" timeout 45 Cli -p 15 -c "$commands"
}
restore() {
  if [[ -n "$paused" ]]; then docker unpause "$prefix-$paused" >/dev/null; paused=''; fi
  if [[ -n "$port_node" ]]; then port "$port_node" 'no shutdown'; port_node=''; fi
}
trap restore EXIT
ready() {
  for attempt in {1..18}; do
    if docker exec "$prefix-h1" ping -n -I eth2 -c 3 -i 0.2 -W 2 192.168.30.12 | grep -q ', 0% packet loss' &&
       docker exec "$prefix-h2" ping -n -I eth2 -c 3 -i 0.2 -W 2 192.168.20.11 | grep -q ', 0% packet loss'; then return; fi
    sleep 5
  done
  echo 'FAIL: L3 did not recover'; return 1
}
fully_restored() {
  for attempt in {1..18}; do
    local good=true
    for node in dc1-leaf dc1-spine1 dc1-spine2; do
      docker exec "$prefix-$node" timeout 45 Cli -p 15 -c 'show bgp evpn summary | json' > "$out/$label-$node-evpn.json"
      jq -e '.vrfs.default.peers | length == 2 and all(.[]; .peerState == "Established")' "$out/$label-$node-evpn.json" >/dev/null || good=false
      docker exec "$prefix-$node" timeout 45 Cli -p 15 -c 'show bfd peers' > "$out/$label-$node-bfd.txt"
      [[ $(grep -cE ' +Up$' "$out/$label-$node-bfd.txt") == 2 ]] || good=false
    done
    docker exec "$prefix-dc2-leaf" timeout 45 sr_cli -d 'show network-instance default protocols bgp summary' > "$out/$label-nokia-bgp.txt"
    grep -Eq 'Total UP peers +: *4$' "$out/$label-nokia-bgp.txt" || good=false
    if [[ "$good" == true ]]; then return; fi
    sleep 5
  done
  echo 'FAIL: complete gateway control-plane restoration'; return 1
}
label=baseline
ready; fully_restored
for spec in 'pause-spine1 dc1-spine1 pause' 'pause-spine2 dc1-spine2 pause' 'dci-1-down dc1-spine1 port' 'dci-2-down dc1-spine2 port'; do
  read -r label node kind <<< "$spec"
  echo "FAULT $label $(date -u +%FT%T.%NZ)"
  docker exec "$prefix-h1" timeout -s INT 45 ping -n -D -I eth2 -i 0.2 -c 200 -W 1 192.168.30.12 > "$out/$label-forward.txt" 2>&1 &
  fwd=$!
  docker exec "$prefix-h2" timeout -s INT 45 ping -n -D -I eth2 -i 0.2 -c 200 -W 1 192.168.20.11 > "$out/$label-reverse.txt" 2>&1 &
  rev=$!
  sleep 1
  if [[ "$kind" == pause ]]; then paused=$node; docker pause "$prefix-$node" >/dev/null; else port_node=$node; port "$node" shutdown; fi
  sleep 8
  ready
  docker exec "$prefix-dc1-leaf" timeout 45 Cli -p 15 -c 'show ip route vrf TENANT' > "$out/$label-arista-tenant.txt"
  docker exec "$prefix-dc2-leaf" timeout 45 sr_cli -d 'show network-instance TENANT ipv4 route all' > "$out/$label-nokia-tenant.txt"
  echo "PASS $label: bidirectional L3 with fault present"
  restore
  ready; fully_restored
  wait "$fwd" || true; wait "$rev" || true
  echo "PASS $label: restored"
done
trap - EXIT
echo 'PASS: both gateway endpoint failures and both DCI-link failures; restored'
