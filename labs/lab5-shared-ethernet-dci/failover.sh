#!/usr/bin/env bash
# Inject one Lab 5 fault at a time. Restore pending faults on exit.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-5
out="results/failover-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
fault_node=''; fault_port=''; paused=''
port_state() {
  local node=$1 port=$2 state=$3
  if [[ "$node" == dc1-* ]]; then
    local command=shutdown
    [[ "$state" == enable ]] && command='no shutdown'
    local cli_commands
    printf -v cli_commands 'configure terminal\ninterface %s\n%s' "$port" "$command"
    docker exec "$prefix-$node" timeout 45 Cli -p 15 -c "$cli_commands"
  else
    docker exec "$prefix-$node" timeout 45 sr_cli -ecd "/interface $port admin-state $state"
  fi
}
restore() {
  if [[ -n "$paused" ]]; then docker unpause "$prefix-$paused" >/dev/null; paused=''; fi
  if [[ -n "$fault_node" ]]; then
    port_state "$fault_node" "$fault_port" enable
    fault_node=''; fault_port=''
  fi
}
trap restore EXIT
probe() {
  local result
  for spec in 'h1 eth1 192.168.10.12' 'h2 eth1 192.168.10.11' 'h1 eth2 192.168.30.12' 'h2 eth2 192.168.20.11'; do
    read -r host iface target <<< "$spec"
    result=$(docker exec "$prefix-$host" ping -n -I "$iface" -c 3 -i 0.2 -W 2 "$target") || { echo "$result"; return 1; }
    grep -q ', 0% packet loss' <<< "$result" && ! grep -Eq 'DUP!|duplicates' <<< "$result" || { echo "$result"; return 1; }
  done
}
ready() {
  for attempt in {1..18}; do
    if probe; then return; fi
    sleep 5
  done
  echo 'FAIL: bidirectional L2/L3 did not recover'; return 1
}
healthy() {
  local node=$1 label=$2
  for attempt in {1..18}; do
    if [[ "$node" == dc1-spine* ]]; then
      docker exec "$prefix-$node" timeout 45 Cli -c 'show ip bgp summary vrf TENANT | json' > "$out/$label-bgp.json"
      if jq -e '.vrfs.TENANT.peers | length == 2 and all(.[]; .peerState == "Established")' "$out/$label-bgp.json" >/dev/null; then return; fi
    else
      docker exec "$prefix-$node" timeout 45 sr_cli -d 'show network-instance TENANT protocols bgp summary' > "$out/$label-bgp.txt"
      if grep -Eq 'Total UP peers +: *2$' "$out/$label-bgp.txt"; then return; fi
    fi
    sleep 5
  done
  echo "FAIL: $node did not restore all DCI BGP peers"; return 1
}
scenario() {
  local label=$1 node=$2 port=${3:-} pids=()
  echo "SCENARIO $label START $(date -u +%FT%T.%NZ)"
  ready
  for spec in 'h1 eth1 192.168.10.12 l2-forward' 'h2 eth1 192.168.10.11 l2-reverse' 'h1 eth2 192.168.30.12 l3-forward' 'h2 eth2 192.168.20.11 l3-reverse'; do
    read -r host iface target flow <<< "$spec"
    docker exec "$prefix-$host" timeout -s INT 95 ping -n -D -I "$iface" -i 0.2 -c 450 -W 1 "$target" > "$out/$label-$flow.txt" 2>&1 &
    pids+=("$!")
  done
  sleep 1
  echo "FAULT $label $(date -u +%FT%T.%NZ)"
  if [[ -z "$port" ]]; then
    paused=$node; docker pause "$prefix-$node" >/dev/null
  else
    fault_node=$node; fault_port=$port; port_state "$node" "$port" disable
  fi
  sleep 8
  ready
  docker exec "$prefix-h1" ip neigh flush dev eth1
  docker exec "$prefix-h2" ip neigh flush dev eth1
  ready
  echo "PASS $label: bidirectional L2/L3 and fresh ARP with fault present"
  echo "RESTORE $label $(date -u +%FT%T.%NZ)"
  restore
  ready
  for check_node in dc1-spine1 dc1-spine2 dc2-bl dc2-bl2; do healthy "$check_node" "$label-restored-$check_node"; done
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  echo "PASS $label: all nodes restored"
}
ready
for node in dc1-spine1 dc1-spine2 dc2-bl dc2-bl2; do healthy "$node" "baseline-$node"; done
if [[ ${1:-all} == spines ]]; then
  for node in dc1-spine1 dc1-spine2; do scenario "pause-$node" "$node"; done
  echo 'PASS: both isolated Arista spine freeze scenarios, all peers restored'
else
for node in dc1-spine1 dc1-spine2 dc2-bl dc2-bl2; do scenario "pause-$node" "$node"; done
scenario dci-1-down dc1-spine1 Ethernet2
scenario dci-2-down dc1-spine2 Ethernet2
scenario arista-uplink-1-down dc1-leaf Ethernet1
scenario nokia-uplink-2-down dc2-leaf ethernet-1/4
scenario arista-peer-link-down dc1-spine1 Ethernet3
echo 'PASS: all 9 isolated single-fault scenarios. Simulator observations, not an ASIC convergence SLA.'
fi
