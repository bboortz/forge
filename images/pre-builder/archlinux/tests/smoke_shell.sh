#!/usr/bin/env bash
# Smoke: /bin/bash present (Arch default). Operators can docker exec bash.
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE}" /bin/bash -c "echo ok")
[[ "${out}" == "ok" ]] || { echo "  ✗ bash did not echo 'ok': ${out}" >&2; exit 1; }
echo "  ✓ /bin/bash functional"
