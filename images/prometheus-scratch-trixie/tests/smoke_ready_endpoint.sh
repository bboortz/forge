#!/usr/bin/env bash
# Smoke — GET /-/ready returns 200 (initial scrape loop primed).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 9090 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/-/ready' \
  --test  'curl -sf http://localhost:__HOST_PORT__/-/ready | grep -q "Ready"' \
  --timeout 30
echo "  ✓ GET /-/ready returns 200 (Prometheus Server is Ready.)"
