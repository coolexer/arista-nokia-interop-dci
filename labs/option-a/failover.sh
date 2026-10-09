#!/usr/bin/env bash
# Fault injection in this lab only. Restores the injected fault on exit.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-a
out="results/failover-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
fault_node=''; fault_port=''; paused=''
restore() {
  if [[ -n "$paused" ]]; then docker unpause "$prefix-$paused" >/dev/null; paused=''; fi
  if [[ -n "$fault_node" ]]; then
    docker exec "$prefix-$fault_node" timeout 45 sr_cli -ecd "/interface $fault_port admin-state enable"
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
  echo 'FAIL: L2/L3 did not recover within the bounded retry window'; return 1
}
healthy() {
  local node=$1 label=$2
  for attempt in {1..18}; do
    docker exec "$prefix-$node" timeout 60 sr_cli -d 'info from state /bfd' > "$out/$label-restored-bfd.txt"
    docker exec "$prefix-$node" timeout 60 sr_cli -d 'show network-instance default protocols bgp summary' > "$out/$label-restored-bgp.txt"
    if [[ $(grep -c 'oper-state up' "$out/$label-restored-bfd.txt") == 3 ]] &&
       grep -Eq 'Total UP peers +: *3$' "$out/$label-restored-bgp.txt"; then return; fi
    sleep 5
  done
  echo "FAIL: $node did not restore all BFD/BGP sessions"; return 1
}
scenario() {
  local label=$1 node=$2 port=${3:-} pids=()
  echo "SCENARIO $label START $(date -u +%FT%T.%NZ)"
  ready
  for spec in 'h1 eth1 192.168.10.12 l2-forward' 'h2 eth1 192.168.10.11 l2-reverse' 'h1 eth2 192.168.30.12 l3-forward' 'h2 eth2 192.168.20.11 l3-reverse'; do
    read -r host iface target flow <<< "$spec"
    docker exec "$prefix-$host" timeout 30 ping -n -D -I "$iface" -i 0.2 -c 120 -W 1 "$target" > "$out/$label-$flow.txt" 2>&1 &
    pids+=("$!")
  done
  sleep 1
  echo "FAULT $label $(date -u +%FT%T.%NZ)"
  if [[ -z "$port" ]]; then
    paused=$node
    docker pause "$prefix-$node" >/dev/null
  else
    fault_node=$node; fault_port=$port
    docker exec "$prefix-$node" timeout 45 sr_cli -ecd "/interface $port admin-state disable"
  fi
  sleep 8
  ready
  # Flush endpoint ARP to verify broadcast/ARP recovery as well as warm unicast.
  docker exec "$prefix-h1" ip neigh flush dev eth1
  docker exec "$prefix-h2" ip neigh flush dev eth1
  ready
  echo "PASS $label: bidirectional L2/L3 and fresh ARP with fault present"
  echo "RESTORE $label $(date -u +%FT%T.%NZ)"
  restore
  ready
  healthy "$node" "$label"
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  echo "PASS $label: restoration"
  sleep 3
}
ready
for node in dc1-bl dc1-bl2 dc2-bl dc2-bl2; do healthy "$node" "baseline-$node"; done
for node in dc1-bl dc1-bl2 dc2-bl dc2-bl2; do scenario "pause-$node" "$node"; done
scenario dci-1-down dc1-bl ethernet-1/2
scenario dci-2-down dc1-bl2 ethernet-1/2
scenario uplink-1-down dc1-bl ethernet-1/1
scenario uplink-2-down dc2-bl2 ethernet-1/1
echo 'PASS: all 8 isolated single-fault scenarios. Ping traces show observed loss; no ASIC/SLA timing claim.'
