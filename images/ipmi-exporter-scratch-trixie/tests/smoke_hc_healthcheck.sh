#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

hc_test="$(docker inspect --format '{{json .Config.Healthcheck.Test}}' "${IMAGE}")"
case "${hc_test}" in
  *'/hc'*'127.0.0.1:9290/metrics'*) ;;
  *) echo "  ✗ HEALTHCHECK.Test unexpected: ${hc_test}" >&2; exit 1 ;;
esac
echo "  ✓ HEALTHCHECK baked (${hc_test})"

CID="fg043-ipmi-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  set +e
  docker exec "${CID}" /hc -t 2 http://127.0.0.1:9290/metrics >/dev/null 2>&1
  rc=$?
  set -e
  [[ "${rc}" -eq 0 ]] && break
  sleep 1
done
[[ "${rc}" -eq 0 ]] || { echo "  ✗ /hc never reached /metrics (rc=${rc})" >&2; exit 1; }
echo "  ✓ /hc http://127.0.0.1:9290/metrics → exit 0"

set +e
docker exec "${CID}" /hc -t 2 http://127.0.0.1:9999/ >/dev/null 2>&1
closed_rc=$?
set -e
[[ "${closed_rc}" -ne 0 ]] || { echo "  ✗ /hc against closed :9999 should exit non-zero" >&2; exit 1; }
echo "  ✓ /hc http://127.0.0.1:9999/ → unhealthy (exit ${closed_rc})"
