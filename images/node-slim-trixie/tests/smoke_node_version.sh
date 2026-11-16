#!/usr/bin/env bash
# Smoke — /usr/local/bin/node exists + reports v24.x.x.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-node-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/node "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ node --version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
case "${out}" in
  v24.*) echo "  ✓ Node.js ${out}" ;;
  *) echo "  ✗ expected Node.js v24.x.x, got: ${out}" >&2; exit 1 ;;
esac
