#!/usr/bin/env bash
# Hold the MLAG peer-link down beyond peer detection timers; keep MGMT alive.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-5
out="results/peer-link-held-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
restore() {
  docker exec "$prefix-dc1-spine1" timeout 45 Cli -p 15 -c $'configure terminal\ninterface Ethernet3\nno shutdown'
}
trap restore EXIT
docker exec "$prefix-dc1-spine1" timeout 45 Cli -p 15 -c $'configure terminal\ninterface Ethernet3\nshutdown'
echo "PEER LINK DISABLED $(date -u +%FT%T)"
for round in 1 2 3; do
  sleep 25
  pids=()
  for node in dc1-spine1 dc1-spine2; do
    docker exec "$prefix-$node" timeout 45 Cli -p 15 -c 'show mlag detail | json' > "$out/round-$round-$node-mlag.json" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  echo "STATE ROUND $round $(date -u +%FT%T)"
done
for node in dc1-spine1 dc1-spine2; do
  jq -e '.peerLinkStatus == "lowerLayerDown" or .peerLinkStatus == "down"' "$out/round-3-$node-mlag.json" >/dev/null
  jq -e '.detail.udpHeartbeatAlive == true' "$out/round-3-$node-mlag.json" >/dev/null
done
blocked=$(jq -s '[.[] | select(.dualPrimaryPortsErrdisabled == true)] | length' "$out/"round-3-*-mlag.json)
[[ "$blocked" == 1 ]] || { echo "FAIL: expected exactly one guarded MLAG peer, got $blocked"; exit 1; }
for spec in 'h1 eth1 192.168.10.12' 'h2 eth1 192.168.10.11' 'h1 eth2 192.168.30.12' 'h2 eth2 192.168.20.11'; do
  read -r host iface target <<< "$spec"
  docker exec "$prefix-$host" ip neigh flush dev "$iface"
  docker exec "$prefix-$host" ping -n -I "$iface" -c 1 -W 2 "$target" >/dev/null || true
  result=$(docker exec "$prefix-$host" ping -n -I "$iface" -c 5 -i 0.2 -W 2 "$target")
  echo "$result"
  grep -q ', 0% packet loss' <<< "$result"
  ! grep -Eq 'DUP!|duplicates' <<< "$result"
done
./bum.sh
echo 'PASS: sustained peer-link failure, live MGMT heartbeat, one guarded peer, bidirectional L2/L3 and broadcast delivery'
restore
trap - EXIT
echo "PEER LINK RESTORED $(date -u +%FT%T)"
