#!/usr/bin/env bash
set -euo pipefail
: "${IMAGE_NAME:=builder/zig-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/bin/sh "${IMAGE_REF}" -c 'test -s /etc/ssl/certs/ca-certificates.crt' \
  || { echo "  ✗ /etc/ssl/certs/ca-certificates.crt missing or empty" >&2; exit 1; }
echo "  ✓ /etc/ssl/certs/ca-certificates.crt present"
