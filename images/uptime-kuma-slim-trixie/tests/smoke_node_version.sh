#!/usr/bin/env bash
# Smoke — Node.js runtime is v22.x (matches upstream engines field).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/node "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ node --version exited ${rc}: ${out}" >&2
  exit 1
fi
case "${out}" in
  v22.*) ;;
  *) echo "  ✗ expected Node v22.x, got: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ Node.js ${out}"
