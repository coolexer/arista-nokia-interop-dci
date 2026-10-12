#!/usr/bin/env bash
# Lab 3 service isolation and complete DCI loss. Restores pending changes.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-3
out="results/isolation-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
active=none
rt() {
  printf 'delete / network-instance %s protocols bgp-vpn bgp-instance 1 route-target import-rt\nset / network-instance %s protocols bgp-vpn bgp-instance 1 route-target import-rt %s\n' "$1" "$1" "$2" |
    docker exec -i "$prefix-dc2-leaf" timeout 45 sr_cli -ecd
}
dci() {
  local command=shutdown
  [[ "$1" == enable ]] && command='no shutdown'
  for spine in dc1-spine1 dc1-spine2; do
    local cli_commands
    printf -v cli_commands 'configure terminal\ninterface Ethernet2\n%s' "$command"
    docker exec "$prefix-$spine" timeout 45 Cli -p 15 -c "$cli_commands"
  done
}
restore() {
  case "$active" in l2) rt L2-10 target:65000:10010 ;; l3) rt TENANT target:65000:50000 ;; dci) dci enable ;; esac
}
trap restore EXIT
success() {
  local output
  output=$(docker exec "$prefix-h2" ping -n -I "$1" -c 3 -i 0.2 -W 1 "$2") || { echo "$output"; return 1; }
  echo "$output"
  grep -q ', 0% packet loss' <<< "$output"
}
failure() {
  local output
  if output=$(docker exec "$prefix-h2" ping -n -I "$1" -c 3 -i 0.2 -W 1 "$2" 2>&1); then
    echo "$output"; echo 'FAIL: unexpected connectivity'; return 1
  fi
  echo "$output"
  # Accept either zero replies or a NOS-generated unreachable, not a tooling error.
  grep -Eq '0 received|Network unreachable' <<< "$output"
}
recovered() {
  for attempt in {1..18}; do
    if success eth1 192.168.10.11 && success eth2 192.168.20.11; then return; fi
    sleep 5
  done
  echo 'FAIL: services did not recover'; return 1
}
recovered
echo 'TEST L2 import-RT mismatch'
active=l2; rt L2-10 target:65000:99910; sleep 5
docker exec "$prefix-h2" ip neigh flush dev eth1
failure eth1 192.168.10.11
success eth2 192.168.20.11
restore; active=none; sleep 3; recovered
echo 'PASS: L2 isolated; L3 unaffected; L2 restored'
echo 'TEST L3 import-RT mismatch'
active=l3; rt TENANT target:65000:99900; sleep 5
failure eth2 192.168.20.11
success eth1 192.168.10.11
restore; active=none; sleep 3; recovered
echo 'PASS: L3 isolated; L2 unaffected; L3 restored'
echo 'TEST both DCI ports down, both spines remain running'
active=dci; dci disable; sleep 5
failure eth1 192.168.10.11
failure eth2 192.168.20.11
restore; active=none; sleep 5; recovered
trap - EXIT
echo 'PASS: service isolation and complete DCI-loss checks; changes restored'
