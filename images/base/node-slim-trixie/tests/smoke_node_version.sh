#!/usr/bin/env bash
# Smoke: Node 24 LTS present.
set -euo pipefail

: "${IMAGE_NAME:=base/node-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE_REF}" --version)
case "${out}" in
  v24.*) echo "  ✓ Node ${out}" ;;
  *) echo "  ✗ expected v24.*, got: ${out}" >&2; exit 1 ;;
esac
