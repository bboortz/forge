#!/usr/bin/env bash
# Smoke — nginx actually serves 200 on / with the default welcome page.
# Uses scripts/smoke-server.sh so the start-wait-probe-stop pattern is
# shared with every future server image (postgres, redis, …).
#
# Delivers: FG-006 Scenario "nginx serves 200 on /".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 80 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/' \
  --test  'curl -sf http://localhost:__HOST_PORT__/ | grep -q "Welcome to nginx"' \
  --timeout 10
echo "  ✓ GET / returns 200 with the default welcome page"
