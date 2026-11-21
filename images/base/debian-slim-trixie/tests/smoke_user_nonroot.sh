#!/usr/bin/env bash
# Smoke: container runs as uid 65532 by default.
set -euo pipefail

: "${IMAGE_NAME:=base/debian-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

uid=$(docker run --rm --entrypoint=/usr/bin/id "${IMAGE_REF}" -u)
[[ "${uid}" == "65532" ]] || { echo "  ✗ expected uid 65532, got: ${uid}" >&2; exit 1; }
echo "  ✓ default uid is 65532"
