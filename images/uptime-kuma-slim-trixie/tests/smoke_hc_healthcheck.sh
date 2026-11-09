#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

hc_test="$(docker inspect --format '{{json .Config.Healthcheck.Test}}' "${IMAGE}")"
case "${hc_test}" in
  *'/hc'*'127.0.0.1:3001/api/entry-page'*) ;;
  *) echo "  ✗ HEALTHCHECK.Test unexpected: ${hc_test}" >&2; exit 1 ;;
esac
echo "  ✓ HEALTHCHECK baked (${hc_test})"

CID="fg045-uk-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null
rc=1
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  set +e
  docker exec "${CID}" /hc -t 2 http://127.0.0.1:3001/api/entry-page >/dev/null 2>&1
  rc=$?
  set -e
  [[ "${rc}" -eq 0 ]] && break
  sleep 1
done
[[ "${rc}" -eq 0 ]] || { echo "  ✗ /hc never reached /api/entry-page (rc=${rc})" >&2; docker logs "${CID}" | tail -20; exit 1; }
echo "  ✓ /hc http://127.0.0.1:3001/api/entry-page → exit 0"

set +e
docker exec "${CID}" /hc -t 2 http://127.0.0.1:9999/ >/dev/null 2>&1
closed_rc=$?
set -e
[[ "${closed_rc}" -ne 0 ]] || { echo "  ✗ /hc against closed :9999 should exit non-zero" >&2; exit 1; }
echo "  ✓ /hc http://127.0.0.1:9999/ → unhealthy (exit ${closed_rc})"
