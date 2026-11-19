#!/usr/bin/env bash
# Smoke — /usr/local/bin/zig exists + reports a 0.x pre-1.0 version.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-zig-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/zig "${IMAGE}" version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ zig version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
# Zig is pre-1.0; version strings look like "0.14.1" or "0.15.0-dev.<n>+<sha>".
case "${out}" in
  0.*) echo "  ✓ zig version = ${out}" ;;
  *) echo "  ✗ expected 0.*, got: ${out}" >&2; exit 1 ;;
esac
