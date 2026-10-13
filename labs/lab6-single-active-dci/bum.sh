#!/usr/bin/env bash
# Count broadcast ARP delivery in both directions.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-6
out="results/bum-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee "$out/test.log") 2>&1
for spec in 'h1 h2 192.168.10.11 192.168.10.12 forward' 'h2 h1 192.168.10.12 192.168.10.11 reverse'; do
  read -r sender receiver src dst label <<< "$spec"
  docker exec -u 0 "$prefix-$receiver" timeout -s INT 12 tcpdump -l -n -i eth1 \
    "arp and arp[6:2] = 1 and src host $src and dst host $dst" > "$out/$label-received.txt" 2>&1 &
  capture=$!
  trap 'kill "$capture" 2>/dev/null || true' EXIT
  sleep 1
  docker exec "$prefix-$sender" arping -b -c 5 -I eth1 "$dst" > "$out/$label-sent.txt"
  wait "$capture" || true
  trap - EXIT
  count=$(grep -c 'ARP, Request who-has' "$out/$label-received.txt" || true)
  echo "$label: sent 5 broadcast requests; remote client received $count"
  [[ "$count" == 5 ]] || { echo 'FAIL: missing/duplicate broadcast requests'; exit 1; }
done
echo 'PASS: exactly five ARP broadcasts delivered per direction'
