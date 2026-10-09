#!/usr/bin/env bash
# Read-only checks. Does not deploy containers, pull images or configure a NOS.
set -euo pipefail
cd -- "$(dirname -- "$0")"
command -v containerlab >/dev/null
command -v docker >/dev/null
docker info >/dev/null
containerlab version | tail -n 5
for f in configs/dc1-leaf.cfg configs/dc1-bl.cli configs/dc2-bl.cli configs/dc1-bl2.cli configs/dc2-bl2.cli configs/dc2-leaf.cli configs/host-init.sh; do
  test -s "$f" || { echo "Missing config: $f" >&2; exit 1; }
done
for script in preflight.sh verify.sh failover.sh bum.sh configs/host-init.sh; do
  bash -n "$script"
done
containerlab graph --offline --mermaid --topo interop-dci-b.clab.yml > /dev/null
status=0
if [[ ! -s srl.license ]]; then
  echo 'MISSING: srl.license (SR Linux license for X1b emulation).'
  status=1
fi
for image in arista_ceos:4.34.7M srlinux:26.7.1 network-multitool:latest; do
  if docker image inspect "$image" > /dev/null 2>&1; then
    echo "LOCAL IMAGE OK: $image"
  else
    echo "MISSING LOCAL IMAGE: $image (pull separately before deployment)."
    status=1
  fi
done
echo 'Only static/preflight checks performed; no lab was started.'
exit "$status"
