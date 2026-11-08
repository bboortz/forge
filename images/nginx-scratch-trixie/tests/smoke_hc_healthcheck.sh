#!/usr/bin/env bash
# Smoke — nginx-scratch-trixie ships /hc; docker-native healthcheck via
# /hc against the built-in /healthz endpoint succeeds, and against a
# closed port fails. Also waits for docker's HEALTHCHECK to transition
# Status → "healthy".
#
# Delivers: FG-031 Scenarios "nginx ships /hc + auto-healthchecks" and
#           "nginx /healthz answers 200 end-to-end".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CID="fg031-nginx-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: boot + exec /hc against /healthz"
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null

# Wait for nginx to start accepting connections (healthcheck has
# --start-period=5s + --interval=30s, so docker's own status won't flip
# to healthy until the first interval; exec'ing /hc directly is faster).
for _ in 1 2 3 4 5 6 7 8 9 10; do
  set +e
  docker exec "${CID}" /hc -t 2 http://127.0.0.1/healthz >/dev/null 2>&1
  rc=$?
  set -e
  [[ "${rc}" -eq 0 ]] && break
  sleep 1
done
[[ "${rc}" -eq 0 ]] || {
  echo "  ✗ /hc never succeeded against /healthz (last rc=${rc})" >&2
  docker logs "${CID}" >&2 || true
  exit 1
}
echo "  ✓ /hc http://127.0.0.1/healthz → healthy (exit 0)"

# Closed port should return non-zero.
set +e
docker exec "${CID}" /hc -t 2 http://127.0.0.1:9999/ >/dev/null 2>&1
closed_rc=$?
set -e
if [[ "${closed_rc}" -eq 0 ]]; then
  echo "  ✗ /hc against closed :9999 should exit non-zero, got 0" >&2
  exit 1
fi
echo "  ✓ /hc http://127.0.0.1:9999/ → unhealthy (exit ${closed_rc})"

# Healthcheck baked in Dockerfile — docker inspect should show Test set.
hc_test="$(docker inspect --format '{{json .Config.Healthcheck.Test}}' "${IMAGE}")"
case "${hc_test}" in
  *'/hc'*'/healthz'*) ;;
  *) echo "  ✗ docker inspect Healthcheck.Test unexpected: ${hc_test}" >&2; exit 1 ;;
esac
echo "  ✓ HEALTHCHECK baked into image (${hc_test})"
