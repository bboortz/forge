#!/usr/bin/env bash
# Smoke: uid 65532.
set -euo pipefail

: "${IMAGE_NAME:=base/node-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

uid=$(docker run --rm "${IMAGE_REF}" -e "process.stdout.write(String(process.getuid()))")
[[ "${uid}" == "65532" ]] || { echo "  ✗ expected uid 65532, got: ${uid}" >&2; exit 1; }
echo "  ✓ default uid is 65532"
