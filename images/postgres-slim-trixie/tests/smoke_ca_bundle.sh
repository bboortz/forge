#!/usr/bin/env bash
# Smoke: /etc/ssl/certs/ca-certificates.crt present and readable.
set -euo pipefail

: "${IMAGE_NAME:=postgres-slim-trixie}"
: "${IMAGE_TAG:=18}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE_REF}: /etc/ssl/certs/ca-certificates.crt present"
docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -s /etc/ssl/certs/ca-certificates.crt
echo "  ✓ CA bundle present"
