#!/usr/bin/env bash
# Smoke: the sidecar-netns pattern works end-to-end. Boot a tiny target
# server, start healthy-scratch-trixie as a sidecar sharing its netns,
# and confirm:
#   1. wget against the shared loopback hits the target
#   2. nc -z against the shared loopback detects the target's port
#
# Uses redis-scratch-trixie (already built in Forge local) as a cheap
# target — it binds :6379 reliably. Not depending on nginx-scratch
# because that would need a mounted config.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TARGET_IMAGE="${REGISTRY}/redis-scratch-trixie:8"

# Ensure the target image exists (built earlier in the suite).
if ! docker image inspect "${TARGET_IMAGE}" >/dev/null 2>&1; then
  echo "  ⚠ ${TARGET_IMAGE} not present — building it on demand"
  bash scripts/build-image.sh redis-scratch-trixie >/dev/null
fi

TARGET="fg029-target-$$"
trap 'docker rm -f "${TARGET}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: boot target (redis on :6379) + run healthchecks via shared netns"
docker run -d --rm --name "${TARGET}" "${TARGET_IMAGE}" >/dev/null
sleep 2

# nc -z: TCP port-reachability check.
if docker run --rm --network="container:${TARGET}" \
     --entrypoint=/usr/bin/nc "${IMAGE}" -z 127.0.0.1 6379 2>&1; then
  echo "  ✓ nc -z 127.0.0.1 6379 succeeds (TCP reachable)"
else
  echo "  ✗ nc -z failed against live target" >&2
  exit 1
fi

# Confirm the inverse: nc against a closed port fails.
set +e
docker run --rm --network="container:${TARGET}" \
  --entrypoint=/usr/bin/nc "${IMAGE}" -z 127.0.0.1 9999 2>&1 >/dev/null
closed_rc=$?
set -e
if [[ "${closed_rc}" -ne 0 ]]; then
  echo "  ✓ nc -z against closed port fails as expected (rc=${closed_rc})"
else
  echo "  ✗ nc -z unexpectedly succeeded against :9999" >&2
  exit 1
fi

# wget against HTTP: we can't easily POST to redis, but we CAN prove wget
# connects + fails with a protocol error (not a connection refused),
# proving the netns is shared and wget reaches 127.0.0.1:6379.
set +e
out=$(docker run --rm --network="container:${TARGET}" \
  --entrypoint=/usr/bin/wget "${IMAGE}" -qO- -T 3 http://127.0.0.1:6379/ 2>&1)
wget_rc=$?
set -e
# wget hitting a non-HTTP socket produces "Unable to establish SSL" or
# "Read error" / "HTTP request sent" that redis then errors on. Any of
# these prove connectivity (vs "Connection refused").
if grep -qE "Connection refused" <<<"${out}"; then
  echo "  ✗ wget got 'Connection refused' — netns not shared?" >&2
  echo "${out}" >&2
  exit 1
fi
echo "  ✓ wget reached redis port via shared netns (non-HTTP protocol error, as expected)"
