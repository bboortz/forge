#!/usr/bin/env bash
# Smoke — /etc/ssl/certs/ca-certificates.crt is present.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-debian-slim-sid}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c 'test -s /etc/ssl/certs/ca-certificates.crt' \
  || { echo "  ✗ /etc/ssl/certs/ca-certificates.crt missing or empty" >&2; exit 1; }
echo "  ✓ /etc/ssl/certs/ca-certificates.crt present"
