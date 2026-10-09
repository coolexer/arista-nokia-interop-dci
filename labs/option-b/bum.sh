#!/usr/bin/env bash
# Check that five broadcast ARP requests cross the DCI exactly once each.
set -euo pipefail
cd -- "$(dirname -- "$0")"
prefix=clab-interop-dci-b
out="results/bum-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
docker exec -u 0 "$prefix-h2" timeout 15 tcpdump -l -n -i eth1 \
  'arp and arp[6:2] = 1 and src host 192.168.10.11 and dst host 192.168.10.12' > "$out/received-arp.txt" 2>&1 &
capture=$!
trap 'kill "$capture" 2>/dev/null || true' EXIT
sleep 1
docker exec "$prefix-h1" arping -b -c 5 -I eth1 192.168.10.12 > "$out/sent-arp.txt"
wait "$capture" || true
trap - EXIT
count=$(grep -c 'ARP, Request who-has' "$out/received-arp.txt" || true)
echo "Sent 5 broadcast requests; remote client received $count" | tee "$out/test.log"
[[ "$count" == 5 ]] || { echo 'FAIL: missing/duplicate ARP requests'; exit 1; }
echo 'PASS: no duplicate delivery in the five-packet broadcast sample' | tee -a "$out/test.log"
