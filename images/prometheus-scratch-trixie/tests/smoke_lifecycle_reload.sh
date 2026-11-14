#!/usr/bin/env bash
# Smoke — --web.enable-lifecycle supports POST /-/reload.
#
# Homelab's compose passes --web.enable-lifecycle so operators can hot-
# reload prometheus.yml via POST /-/reload (per ansible/roles/monitoring
# handler "reload prometheus"). Catches a regression where the from-source
# build somehow disables the lifecycle API (e.g. missing build tag, or
# upstream removing the endpoint in a future bump).
#
# Delivers: FG-048 homelab-compat scenario "lifecycle reload works".

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CID="fg048-lifecycle-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT

# Start with --web.enable-lifecycle in addition to the baked CMD flags.
docker run -d --rm --name "${CID}" -p 0:9090 "${IMAGE}" \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.console.libraries=/usr/share/prometheus/console_libraries \
  --web.console.templates=/usr/share/prometheus/consoles \
  --web.listen-address=:9090 \
  --web.enable-lifecycle >/dev/null

PORT=$(docker port "${CID}" 9090/tcp | head -1 | awk -F: '{print $NF}')
[[ -n "${PORT}" ]] || { echo "  ✗ could not resolve host port" >&2; exit 1; }

# Wait for /-/healthy.
deadline=$(( $(date +%s) + 20 ))
until curl -sf -o /dev/null "http://localhost:${PORT}/-/healthy" 2>/dev/null; do
  (( $(date +%s) < deadline )) || { echo "  ✗ /-/healthy timed out" >&2; exit 1; }
  sleep 0.5
done

# POST /-/reload must return 200 OK when lifecycle API is enabled.
set +e
reload_code=$(curl -s -X POST -o /dev/null -w '%{http_code}' \
  "http://localhost:${PORT}/-/reload")
set -e

if [[ "${reload_code}" != "200" ]]; then
  echo "  ✗ POST /-/reload returned ${reload_code} — --web.enable-lifecycle broken" >&2
  docker logs "${CID}" 2>&1 | tail -10 >&2
  exit 1
fi
echo "  ✓ --web.enable-lifecycle supports POST /-/reload (homelab compat)"
