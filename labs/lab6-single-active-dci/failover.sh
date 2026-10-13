#!/usr/bin/env bash
# Test one fault at a time and always restore injected state.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-6
case_name=${1:?Specify a fault name}
out="results/$case_name-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
paused=''; fault_node=''; fault_port=''; extra_port=''; group_node=''
port_state() {
  local node=$1 port=$2 state=$3 cmd
  if [[ "$node" == dc1-* ]]; then
    cmd=shutdown; [[ $state == enable ]] && cmd='no shutdown'
    printf -v cmd 'configure terminal\ninterface %s\n%s' "$port" "$cmd"
    docker exec "$prefix-$node" timeout 40 Cli -p 15 -c "$cmd"
  else
    docker exec "$prefix-$node" timeout 40 sr_cli -ecd "/interface $port admin-state $state"
  fi
}
restore() {
  [[ -z $paused ]] || { docker unpause "$prefix-$paused" >/dev/null; paused=''; }
  [[ -z $group_node ]] || { docker exec "$prefix-$group_node" timeout 40 sr_cli -ecd '/network-instance default protocols bgp group OVERLAY admin-state enable'; group_node=''; }
  [[ -z $extra_port ]] || { port_state "$fault_node" "$extra_port" enable; extra_port=''; }
  [[ -z $fault_node ]] || { port_state "$fault_node" "$fault_port" enable; fault_node=''; }
}
trap restore EXIT
probe() {
  local result
  for spec in 'h1 eth1 192.168.10.12' 'h2 eth1 192.168.10.11' 'h1 eth2 192.168.30.12' 'h2 eth2 192.168.20.11'; do
    read -r host iface target <<< "$spec"
    result=$(docker exec "$prefix-$host" ping -n -I "$iface" -c 3 -i 0.2 -W 1 "$target") || { echo "$result"; return 1; }
    grep -q ', 0% packet loss' <<< "$result" && ! grep -Eq 'DUP!|duplicates' <<< "$result" || { echo "$result"; return 1; }
  done
}
ready() {
  for attempt in {1..8}; do
    if probe; then return 0; fi
    sleep 5
  done
  return 1
}
ready || { echo 'FAIL: initial services'; exit 1; }
case "$case_name" in
  dci1) fault_node=dc1-spine1; fault_port=Ethernet2;;
  dci2) fault_node=dc1-spine2; fault_port=Ethernet2;;
  arista-uplink1) fault_node=dc1-spine1; fault_port=Ethernet1;;
  arista-uplink2) fault_node=dc1-spine2; fault_port=Ethernet1;;
  nokia-uplink1) fault_node=dc2-bl; fault_port=ethernet-1/1;;
  nokia-uplink2) fault_node=dc2-bl2; fault_port=ethernet-1/1;;
  nokia-core1) fault_node=dc2-bl; fault_port=ethernet-1/1; extra_port=ethernet-1/3;;
  nokia-core2) fault_node=dc2-bl2; fault_port=ethernet-1/1; extra_port=ethernet-1/3;;
  nokia-peer) fault_node=dc2-bl; fault_port=ethernet-1/3;;
  evpn-core1) group_node=dc2-bl;;
  evpn-core2) group_node=dc2-bl2;;
  pause-spine1) paused=dc1-spine1;;
  pause-spine2) paused=dc1-spine2;;
  pause-bl1) paused=dc2-bl;;
  pause-bl2) paused=dc2-bl2;;
  *) echo 'Unknown fault'; exit 2;;
esac
pids=()
for spec in 'h1 eth1 192.168.10.12 l2-forward' 'h2 eth1 192.168.10.11 l2-reverse' 'h1 eth2 192.168.30.12 l3-forward' 'h2 eth2 192.168.20.11 l3-reverse'; do
 read -r host iface target flow <<< "$spec"
 docker exec "$prefix-$host" timeout -s INT 60 ping -n -D -I "$iface" -i 0.2 -c 250 -W 1 "$target" > "$out/$flow.txt" 2>&1 &
 pids+=("$!")
done
sleep 1
echo "FAULT $case_name $(date -u +%FT%T.%NZ)"
if [[ -n $paused ]]; then
 docker pause "$prefix-$paused" >/dev/null
elif [[ -n $group_node ]]; then
 docker exec "$prefix-$group_node" timeout 40 sr_cli -ecd '/network-instance default protocols bgp group OVERLAY admin-state disable'
else
 port_state "$fault_node" "$fault_port" disable
 [[ -z $extra_port ]] || port_state "$fault_node" "$extra_port" disable
fi
sleep 5
rc=0
if ready; then
 docker exec "$prefix-h1" ip neigh flush dev eth1
 docker exec "$prefix-h2" ip neigh flush dev eth1
 if ready; then echo "PASS $case_name: L2/L3 both directions and fresh ARP with fault held"; else rc=1; fi
else rc=1; fi
[[ $rc == 0 ]] || echo "FAIL $case_name: services did not recover while fault held"
echo "RESTORE $case_name $(date -u +%FT%T.%NZ)"
restore
ready || { echo 'FAIL: restored services'; rc=1; }
for pid in "${pids[@]}"; do wait "$pid" || true; done
exit "$rc"
