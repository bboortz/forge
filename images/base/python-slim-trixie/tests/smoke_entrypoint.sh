#!/usr/bin/env bash
# Smoke: ENTRYPOINT = python3; `docker run <image> -c "..."` runs Python directly.
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE_REF}" -c "print('ok')")
[[ "${out}" == "ok" ]] || { echo "  ✗ expected 'ok', got: ${out}" >&2; exit 1; }
echo '  ✓ ENTRYPOINT=python3 confirmed; docker run <image> -c "..." works'
