#!/usr/bin/env bash
# Inject one Lab 3 fault at a time. Restore pending faults on exit.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-3
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
  docker exec "$prefix-h1" ping -n -I eth1 -c 3 -i 0.2 -W 2 192.168.10.12 | grep -q ', 0% packet loss' &&
  docker exec "$prefix-h2" ping -n -I eth1 -c 3 -i 0.2 -W 2 192.168.10.11 | grep -q ', 0% packet loss' &&
  docker exec "$prefix-h1" ping -n -I eth2 -c 3 -i 0.2 -W 2 192.168.30.12 | grep -q ', 0% packet loss' &&
  docker exec "$prefix-h2" ping -n -I eth2 -c 3 -i 0.2 -W 2 192.168.20.11 | grep -q ', 0% packet loss'
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
    if [[ "$node" == dc1-* ]]; then
      docker exec "$prefix-$node" timeout 60 Cli -c 'show ip bgp summary | json' > "$out/$label-bgp.json"
      docker exec "$prefix-$node" timeout 60 Cli -c 'show bfd peers' > "$out/$label-bfd.txt"
      local overlay_ok=true
      if [[ "$node" == dc1-leaf ]]; then
        docker exec "$prefix-$node" timeout 60 Cli -c 'show bgp evpn summary | json' > "$out/$label-evpn.json"
        jq -e '.vrfs.default.peers | length == 1 and all(.[]; .peerState == "Established")' "$out/$label-evpn.json" >/dev/null || overlay_ok=false
      fi
      if jq -e '.vrfs.default.peers | length == 2 and all(.[]; .peerState == "Established")' "$out/$label-bgp.json" >/dev/null &&
         [[ $(grep -cE ' +Up$' "$out/$label-bfd.txt") == 2 && "$overlay_ok" == true ]]; then return; fi
    else
      local expected_bfd=3
      [[ "$node" == dc2-leaf ]] && expected_bfd=2
      docker exec "$prefix-$node" timeout 60 sr_cli -d 'info from state /bfd' > "$out/$label-bfd.txt"
      docker exec "$prefix-$node" timeout 60 sr_cli -d 'show network-instance default protocols bgp summary' > "$out/$label-bgp.txt"
      if [[ $(grep -c 'oper-state up' "$out/$label-bfd.txt") == "$expected_bfd" ]] &&
         grep -Eq 'Total UP peers +: *3$' "$out/$label-bgp.txt"; then return; fi
    fi
    sleep 5
  done
  echo "FAIL: $node did not restore its control-plane peers"; return 1
}
scenario() {
  local label=$1 node=$2 port=${3:-} pids=()
  echo "SCENARIO $label START $(date -u +%FT%T.%NZ)"
  ready
  for spec in 'h1 eth1 192.168.10.12 l2-forward' 'h2 eth1 192.168.10.11 l2-reverse' 'h1 eth2 192.168.30.12 l3-forward' 'h2 eth2 192.168.20.11 l3-reverse'; do
    read -r host iface target flow <<< "$spec"
    docker exec "$prefix-$host" timeout -s INT 45 ping -n -D -I "$iface" -i 0.2 -c 200 -W 1 "$target" > "$out/$label-$flow.txt" 2>&1 &
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
  docker exec "$prefix-dc1-leaf" timeout 45 Cli -c 'show ip route 10.255.2.1' > "$out/$label-arista-vtep-fib.txt"
  docker exec "$prefix-dc2-leaf" timeout 45 sr_cli -d 'show network-instance default ipv4 route 10.255.1.1/32' > "$out/$label-nokia-vtep-fib.txt"
  echo "PASS $label: bidirectional L2/L3 and fresh ARP with fault present"
  echo "RESTORE $label $(date -u +%FT%T.%NZ)"
  restore
  ready
  for check_node in dc1-leaf dc1-spine1 dc1-spine2 dc2-bl dc2-bl2 dc2-leaf; do healthy "$check_node" "$label-restored-$check_node"; done
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  echo "PASS $label: all nodes restored"
}
ready
for node in dc1-leaf dc1-spine1 dc1-spine2 dc2-bl dc2-bl2 dc2-leaf; do healthy "$node" "baseline-$node"; done
for node in dc1-spine1 dc1-spine2 dc2-bl dc2-bl2; do scenario "pause-$node" "$node"; done
scenario dci-1-down dc1-spine1 Ethernet2
scenario dci-2-down dc1-spine2 Ethernet2
scenario arista-uplink-1-down dc1-leaf Ethernet1
scenario nokia-uplink-2-down dc2-leaf ethernet-1/4
echo 'PASS: all 8 isolated single-fault scenarios. Simulator observations, not an ASIC convergence SLA.'
