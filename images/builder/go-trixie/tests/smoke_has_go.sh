#!/usr/bin/env bash
# Smoke: forge-builder-go-trixie carries a working Go toolchain (>= 1.27).
set -euo pipefail
: "${IMAGE_NAME:=forge-builder-go-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/usr/local/go/bin/go "${IMAGE_REF}" version 2>&1)
echo "  → ${out}"

echo "${out}" | grep -qE 'go version go1\.(2[7-9]|[3-9][0-9])' || {
  echo "  ✗ expected Go >= 1.27, got: ${out}" >&2
  exit 1
}
echo "  ✓ Go toolchain >= 1.27 present"
