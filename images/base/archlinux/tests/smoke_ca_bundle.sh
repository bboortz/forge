#!/usr/bin/env bash
# Smoke: CA bundle present (inherited from pre-builder).
set -euo pipefail

: "${IMAGE_NAME:=base/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/test "${IMAGE}" -f /etc/ssl/certs/ca-certificates.crt \
  || { echo "  ✗ CA bundle missing" >&2; exit 1; }
echo "  ✓ CA bundle present"
