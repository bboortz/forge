#!/usr/bin/env bash
# BC-018 test-driver surface: /__driver__/state returns the mock's current
# conversation state. Beaconry's e2e harness uses it to assert hub->telegram
# messages landed.
#
# Delivers: FG-015 Scenario "driver API is reachable".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-telegram-mock}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

ROOT="$(git rev-parse --show-toplevel)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 8080 \
  --ready "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/__driver__/state" \
  --test "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/__driver__/state" \
  --timeout 20

echo "  ✓ /__driver__/state returned 200 (BC-018 driver surface)"
