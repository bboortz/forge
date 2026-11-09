#!/usr/bin/env bash
# Smoke — GET /-/healthy returns 200 with the expected body.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 9090 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/-/healthy' \
  --test  'curl -sf http://localhost:__HOST_PORT__/-/healthy | grep -q "Healthy"' \
  --timeout 30
echo "  ✓ GET /-/healthy returns 200 (Prometheus Server is Healthy.)"
