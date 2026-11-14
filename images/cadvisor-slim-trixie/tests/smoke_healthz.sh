#!/usr/bin/env bash
# Smoke — cadvisor /healthz responds "ok" once boot recovery completes.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cadvisor-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 8080 \
  --run-flags "-v /sys:/sys:ro" \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/healthz' \
  --test  '[[ "$(curl -sf http://localhost:__HOST_PORT__/healthz)" == "ok" ]]' \
  --timeout 20
echo "  ✓ GET /healthz returns \"ok\""
