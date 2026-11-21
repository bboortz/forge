#!/usr/bin/env bash
# Smoke: psitransfer listens on :3000 and serves the upload page.
#
# Uses scripts/smoke-server.sh for the standard "start container, resolve
# host port, curl, teardown" lifecycle (FG-006 pattern).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

: "${IMAGE_NAME:=psitransfer-slim-trixie}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

exec bash scripts/smoke-server.sh \
  --image "${IMAGE}" \
  --port 3000 \
  --ready "curl -fsS --max-time 2 http://127.0.0.1:__HOST_PORT__/ >/dev/null" \
  --test  "curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:__HOST_PORT__/ | grep -q '^200$'" \
  --timeout 30
