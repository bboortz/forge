#!/usr/bin/env bash
# Smoke: CA bundle present for TLS.
set -euo pipefail
: "${IMAGE_NAME:=debian-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -f /etc/ssl/certs/ca-certificates.crt
echo "  ✓ /etc/ssl/certs/ca-certificates.crt present"
