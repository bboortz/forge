#!/usr/bin/env bash
# Smoke: container runs as uid 65532 by default.
set -euo pipefail

: "${IMAGE_NAME:=base/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

uid=$(docker run --rm --entrypoint=/usr/bin/id "${IMAGE}" -u)
[[ "${uid}" == "65532" ]] || { echo "  ✗ expected uid 65532, got: ${uid}" >&2; exit 1; }
echo "  ✓ default uid is 65532"
