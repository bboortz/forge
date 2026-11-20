#!/usr/bin/env bash
# Smoke — /bin/sh and /bin/bash are present (slim contract).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-debian-slim-sid}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c 'echo ok' | grep -qx ok \
  || { echo "  ✗ /bin/sh missing or non-functional" >&2; exit 1; }
docker run --rm --entrypoint=/bin/bash "${IMAGE}" -c 'echo ok' | grep -qx ok \
  || { echo "  ✗ /bin/bash missing or non-functional" >&2; exit 1; }
echo "  ✓ /bin/sh + /bin/bash present (slim contract)"
