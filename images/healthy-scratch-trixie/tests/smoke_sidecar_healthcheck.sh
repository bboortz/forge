#!/usr/bin/env bash
# Smoke: end-to-end sidecar-netns healthcheck. Boot a target service,
# run healthy-scratch-trixie:2 in the shared netns, confirm:
#   1. hc tcp://... succeeds against a live listener (exit 0)
#   2. hc tcp://... fails against a closed port (exit 1)
#
# Uses redis-scratch-trixie :6379 as a cheap target.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
TARGET_IMAGE="${REGISTRY}/redis-scratch-trixie:8"

if ! docker image inspect "${TARGET_IMAGE}" >/dev/null 2>&1; then
  echo "  ⚠ ${TARGET_IMAGE} not present — building on demand"
  bash scripts/build-image.sh redis-scratch-trixie >/dev/null
fi

TARGET="fg030-target-$$"
trap 'docker rm -f "${TARGET}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: boot redis target + healthchecks via shared netns"
docker run -d --rm --name "${TARGET}" "${TARGET_IMAGE}" >/dev/null
sleep 2

# Capture exit without pipefail interference.
set +e
docker run --rm --network="container:${TARGET}" \
  --entrypoint=/hc "${IMAGE}" tcp://localhost:6379 >/dev/null 2>&1
healthy_rc=$?
set -e
if [[ "${healthy_rc}" -ne 0 ]]; then
  echo "  ✗ hc against live :6379 should exit 0, got ${healthy_rc}" >&2
  exit 1
fi
echo "  ✓ hc tcp://localhost:6379 → healthy (exit 0)"

set +e
docker run --rm --network="container:${TARGET}" \
  --entrypoint=/hc "${IMAGE}" tcp://localhost:9999 >/dev/null 2>&1
unhealthy_rc=$?
set -e
if [[ "${unhealthy_rc}" -eq 0 ]]; then
  echo "  ✗ hc against closed :9999 should exit non-zero, got 0" >&2
  exit 1
fi
echo "  ✓ hc tcp://localhost:9999 → unhealthy (exit ${unhealthy_rc})"
