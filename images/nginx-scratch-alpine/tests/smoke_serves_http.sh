#!/usr/bin/env bash
# Smoke: nginx listens on :80 and responds. Accepts HTTP 200 OR 404 — Alpine's
# nginx package ships a default server block that returns 404 for all paths
# by design ("prevents chance access to any other virtualhost"). The smoke
# verifies "nginx is responding" (answered TCP + served some HTTP status).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

: "${IMAGE_NAME:=nginx-scratch-alpine}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

exec bash scripts/smoke-server.sh \
  --image "${IMAGE}" \
  --port 80 \
  --ready "curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:__HOST_PORT__/ | grep -qE '^[0-9]{3}'" \
  --test  "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:__HOST_PORT__/ | grep -qE '^(200|404)'" \
  --timeout 20
