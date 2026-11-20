#!/usr/bin/env bash
# Smoke — CA bundle is present and /bin/sh works (slim contract).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-pre-builder/ubuntu-slim-noble}"
IMAGE_TAG="${IMAGE_TAG:-24.04}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/test "${IMAGE}" -f /etc/ssl/certs/ca-certificates.crt
echo "  ✓ /etc/ssl/certs/ca-certificates.crt present"

docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c 'echo ok' | grep -qx ok
echo "  ✓ /bin/sh present (slim contract)"
