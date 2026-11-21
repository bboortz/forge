#!/usr/bin/env bash
# Smoke: /etc/ssl/certs/ca-certificates.crt present + non-trivial.
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE}" test -s /etc/ssl/certs/ca-certificates.crt \
  || { echo "  ✗ CA bundle missing or empty" >&2; exit 1; }
echo "  ✓ CA bundle present at /etc/ssl/certs/ca-certificates.crt"
