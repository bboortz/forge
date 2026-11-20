#!/usr/bin/env bash
# Smoke: forge-builder-node-trixie carries a working syft binary.
set -euo pipefail
: "${IMAGE_NAME:=forge-builder-node-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/usr/local/bin/syft "${IMAGE_REF}" version 2>&1)
echo "${out}" | head -1

echo "${out}" | grep -q "^Application:.*syft" || {
  echo "  ✗ syft version banner not found" >&2
  echo "${out}" >&2
  exit 1
}
echo "  ✓ syft present + runnable"
