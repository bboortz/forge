#!/usr/bin/env bash
# Smoke — /usr/bin/dumb-init exists + works.
set -euo pipefail
IMAGE_NAME="${IMAGE_NAME:-go-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/dumb-init "${IMAGE}" --version >/dev/null 2>&1 \
  || { echo "  ✗ dumb-init --version failed" >&2; exit 1; }
echo "  ✓ /usr/bin/dumb-init present"
