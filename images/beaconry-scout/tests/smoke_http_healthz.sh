#!/usr/bin/env bash
# Scout boots standalone (no hub, no docker socket) and serves /healthz = 200
# on :8001 — proving the uvicorn FastAPI app came up. In production (compose),
# /readyz returns 200 once the docker socket is mounted; Forge asserts the
# weaker contract: image boots a working HTTP server. Full-readiness
# integration is covered by beaconry's own test suite.
#
# Reuses scripts/smoke-server.sh (FG-006) for the run-wait-probe-stop
# lifecycle.
#
# Delivers: FG-012 Scenario "scout serves /healthz".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-scout}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

ROOT="$(git rev-parse --show-toplevel)"

# Environment scout needs just to boot its HTTP server:
#   HUB_URL — scout POSTs scan results to this; it's fine if it's unreachable
#             since we're not actually scanning anything.
#   SCAN_INTERVAL=3600 — don't fire inside the smoke.
#   SCOUT_HEARTBEAT_INTERVAL_S=0 — no keepalives to a non-existent hub.
#   SCOUT_METRICS_ENABLED=0 — same.
bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 8001 \
  --run-flags "-e HUB_URL=http://hub.invalid:8000 -e HOST_NAME=forge-smoke -e SCAN_INTERVAL=3600 -e SCOUT_HEARTBEAT_INTERVAL_S=0 -e SCOUT_METRICS_ENABLED=0 -e BEACONRY_LOG_LEVEL=WARNING" \
  --ready "curl -sf -o /dev/null --max-time 5 http://localhost:__HOST_PORT__/healthz" \
  --test "curl -sf --max-time 5 http://localhost:__HOST_PORT__/healthz" \
  --timeout 30

echo "  ✓ scout /healthz returned 200 (uvicorn FastAPI app booted)"
