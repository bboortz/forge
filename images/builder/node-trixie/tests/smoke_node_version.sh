#!/usr/bin/env bash
# Smoke: forge-builder-node-trixie carries a working Node toolchain (v24.x LTS).
set -euo pipefail
: "${IMAGE_NAME:=forge-builder-node-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/usr/local/bin/node "${IMAGE_REF}" --version 2>&1)
echo "  → node: ${out}"

case "${out}" in
  v24.*) echo "  ✓ Node 24 LTS present" ;;
  *) echo "  ✗ expected Node v24.*, got: ${out}" >&2; exit 1 ;;
esac
