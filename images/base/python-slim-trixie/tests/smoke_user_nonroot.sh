#!/usr/bin/env bash
# Smoke: container runs as uid 65532 (nonroot baseline).
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

uid=$(docker run --rm "${IMAGE_REF}" -c "import os; print(os.geteuid())")
[[ "${uid}" == "65532" ]] || { echo "  ✗ expected uid 65532, got: ${uid}" >&2; exit 1; }
echo "  ✓ default uid is 65532"
