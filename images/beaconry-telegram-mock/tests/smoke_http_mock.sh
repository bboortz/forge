#!/usr/bin/env bash
# telegram_mock boots and responds to the mock Telegram Bot API path.
# Any token prefix works — mock returns a canned getMe payload.
#
# Delivers: FG-015 Scenario "mock serves /bot/getMe".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-telegram-mock}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

ROOT="$(git rev-parse --show-toplevel)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 8080 \
  --ready "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/bot12345:abc/getMe" \
  --test "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/bot12345:abc/getMe" \
  --timeout 20

echo "  ✓ /bot<token>/getMe returned 200 (mock Telegram Bot API)"
