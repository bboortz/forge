#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-alertmanager-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.28}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 9093 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/-/healthy' \
  --test  'curl -sf -o /dev/null -w "%{http_code}" http://localhost:__HOST_PORT__/-/healthy | grep -q "^200$"' \
  --timeout 30
echo "  ✓ GET /-/healthy returns 200"
