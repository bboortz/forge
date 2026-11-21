#!/usr/bin/env bash
# Smoke: /etc/ssl/certs/ca-certificates.crt present.
set -euo pipefail

: "${IMAGE_NAME:=base/debian-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -f /etc/ssl/certs/ca-certificates.crt \
  || { echo "  ✗ CA bundle missing at /etc/ssl/certs/ca-certificates.crt" >&2; exit 1; }
echo "  ✓ CA bundle present"
