#!/usr/bin/env bash
# Smoke: ENTRYPOINT = node; `docker run <image> -e "..."` runs.
set -euo pipefail

: "${IMAGE_NAME:=base/node-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE_REF}" -e "process.stdout.write('ok')")
[[ "${out}" == "ok" ]] || { echo "  ✗ expected 'ok', got: ${out}" >&2; exit 1; }
echo '  ✓ ENTRYPOINT=node confirmed'
