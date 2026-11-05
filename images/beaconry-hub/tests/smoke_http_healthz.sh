#!/usr/bin/env bash
# Hub boots standalone and serves /healthz = 200 on :8000. Uses
# BEACONRY_SKIP_GRYPE_DB=1 to avoid the ~90s DB download (same as
# beaconry's docker-compose.test.yml). /readyz requires docker socket
# mounted which Forge smoke doesn't do — /healthz suffices.
#
# Delivers: FG-014 Scenario "hub serves /healthz".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-hub}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

ROOT="$(git rev-parse --show-toplevel)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 8000 \
  --run-flags "-e BEACONRY_SKIP_GRYPE_DB=1 -e BEACONRY_NOTIFIER_TELEGRAM_ENABLED=0 -e TELEGRAM_BOT_TOKEN= -e TELEGRAM_CHAT_ID=0 -e BEACONRY_FIX_ENABLED=0 -e BEACONRY_HEARTBEAT_ENABLED=0 -e BEACONRY_RECONCILE_ENABLED=0 -e BEACONRY_LOG_LEVEL=WARNING -e GRYPE_DB_CACHE_DIR=/data/grype-db" \
  --ready "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/healthz" \
  --test "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/healthz" \
  --timeout 60

echo "  ✓ hub /healthz returned 200 (uvicorn FastAPI app booted)"
