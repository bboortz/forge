#!/usr/bin/env bash
# Smoke — /usr/local/go/bin/go exists + reports go1.27.*.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-pre-builder/go-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/go/bin/go "${IMAGE}" version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ go version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
# Upstream golang:1.27-trixie produces output like:
#   go version go1.27.3 linux/amd64
case "${out}" in
  *"go1.27."*) echo "  ✓ ${out}" ;;
  *) echo "  ✗ expected go1.27.*, got: ${out}" >&2; exit 1 ;;
esac
