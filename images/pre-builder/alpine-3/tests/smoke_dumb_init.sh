#!/usr/bin/env bash
# Smoke: /usr/bin/dumb-init present + executable.
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE}" /usr/bin/dumb-init --version >/dev/null \
  || { echo "  ✗ /usr/bin/dumb-init not executable" >&2; exit 1; }
echo "  ✓ dumb-init executable"
