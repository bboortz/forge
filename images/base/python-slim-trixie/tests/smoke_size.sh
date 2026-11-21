#!/usr/bin/env bash
# Smoke: image size ≤ pre-builder/python-slim-trixie × 1.5 (15% headroom
# for /hc layer + LABELs). base/* slim foundations are near-passthroughs of
# their L1 pre-builder parent with only a /hc overlay + USER/ENTRYPOINT metadata.
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
# Resolve parent locally if present, else via ghcr.
PARENT_LOCAL="forge-local/pre-builder/python-slim-trixie:0.1"
PARENT_GHCR="ghcr.io/bboortz/pre-builder/python-slim-trixie:latest"

if docker image inspect "${PARENT_LOCAL}" >/dev/null 2>&1; then
  PARENT_REF="${PARENT_LOCAL}"
else
  PARENT_REF="${PARENT_GHCR}"
  docker image inspect "${PARENT_REF}" >/dev/null 2>&1 || docker pull "${PARENT_REF}" >/dev/null
fi

docker image inspect "${IMAGE_REF}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE_REF} not present — run build-image.sh first" >&2; exit 1; }

size_image=$(docker image inspect --format '{{.Size}}' "${IMAGE_REF}")
size_parent=$(docker image inspect --format '{{.Size}}' "${PARENT_REF}")
# ≤ parent * 1.15 (15% headroom)
limit=$(( size_parent * 150 / 100 ))

if (( size_image > limit )); then
  printf "  ✗ size %d > limit %d (parent=%d × 1.5)\n" "${size_image}" "${limit}" "${size_parent}" >&2
  exit 1
fi
printf "  ✓ size %d ≤ limit %d (parent=%d × 1.5)\n" "${size_image}" "${limit}" "${size_parent}"
