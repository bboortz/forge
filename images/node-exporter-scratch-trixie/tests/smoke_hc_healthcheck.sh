#!/usr/bin/env bash
# Smoke — /hc baked HEALTHCHECK works (docker-native health) + /hc
# can be exec'd directly.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-node-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.12}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 1. HEALTHCHECK instruction baked
hc_test="$(docker inspect --format '{{json .Config.Healthcheck.Test}}' "${IMAGE}")"
case "${hc_test}" in
  *'/hc'*'127.0.0.1:9100/metrics'*) ;;
  *) echo "  ✗ HEALTHCHECK.Test unexpected: ${hc_test}" >&2; exit 1 ;;
esac
echo "  ✓ HEALTHCHECK baked (${hc_test})"

# 2. Boot + exec /hc via docker exec against the live port
CID="fg034-nodex-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  set +e
  docker exec "${CID}" /hc -t 2 http://127.0.0.1:9100/metrics >/dev/null 2>&1
  rc=$?
  set -e
  [[ "${rc}" -eq 0 ]] && break
  sleep 1
done
[[ "${rc}" -eq 0 ]] || { echo "  ✗ /hc never reached /metrics (rc=${rc})" >&2; exit 1; }
echo "  ✓ /hc http://127.0.0.1:9100/metrics → exit 0 (healthy)"

# 3. /hc against closed port → nonzero
set +e
docker exec "${CID}" /hc -t 2 http://127.0.0.1:9999/ >/dev/null 2>&1
closed_rc=$?
set -e
[[ "${closed_rc}" -ne 0 ]] || { echo "  ✗ /hc against closed :9999 should exit non-zero" >&2; exit 1; }
echo "  ✓ /hc http://127.0.0.1:9999/ → unhealthy (exit ${closed_rc})"
