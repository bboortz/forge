#!/usr/bin/env bash
# Smoke: container runs as uid 65532.
set -euo pipefail

: "${IMAGE_NAME:=psitransfer-slim-trixie}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

uid=$(docker run --rm "${IMAGE}" -e "process.stdout.write(String(process.getuid()))")
[[ "${uid}" == "65532" ]] || { echo "  ✗ expected uid 65532, got: ${uid}" >&2; exit 1; }
echo "  ✓ default uid is 65532"
