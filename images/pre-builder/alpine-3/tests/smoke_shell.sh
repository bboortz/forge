#!/usr/bin/env bash
# Smoke: /bin/sh present (Alpine busybox). Operators can docker exec sh.
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE}" /bin/sh -c "echo ok")
[[ "${out}" == "ok" ]] || { echo "  ✗ shell did not echo 'ok': ${out}" >&2; exit 1; }
echo "  ✓ /bin/sh functional"
