#!/usr/bin/env bash
# Smoke: forge-builder-zig-trixie carries a working Zig toolchain (0.*).
set -euo pipefail
: "${IMAGE_NAME:=forge-builder-zig-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/usr/local/bin/zig "${IMAGE_REF}" version 2>&1)
echo "  → ${out}"

case "${out}" in
  0.*) echo "  ✓ Zig pre-1.0 toolchain present (${out})" ;;
  *) echo "  ✗ expected Zig 0.*, got: ${out}" >&2; exit 1 ;;
esac
