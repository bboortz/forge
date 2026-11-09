#!/usr/bin/env bash
# Smoke — uptime-kuma serves the login SPA on :3001.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 3001 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/api/entry-page' \
  --test  'curl -sLf http://localhost:__HOST_PORT__/ | grep -q "Uptime Kuma"' \
  --timeout 30
echo "  ✓ GET / (follow redirects) returns Uptime Kuma SPA"
