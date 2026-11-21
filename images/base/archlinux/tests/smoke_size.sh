#!/usr/bin/env bash
# Smoke: image size ≤ pre-builder/archlinux × 1.15.
set -euo pipefail

: "${IMAGE_NAME:=base/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PARENT_LOCAL="forge-local/pre-builder/archlinux:latest"
PARENT_GHCR="ghcr.io/bboortz/pre-builder/archlinux:latest"

if docker image inspect "${PARENT_LOCAL}" >/dev/null 2>&1; then
  PARENT_REF="${PARENT_LOCAL}"
else
  PARENT_REF="${PARENT_GHCR}"
  docker image inspect "${PARENT_REF}" >/dev/null 2>&1 || docker pull "${PARENT_REF}" >/dev/null
fi

docker image inspect "${IMAGE_REF}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE_REF} not present" >&2; exit 1; }

size_image=$(docker image inspect --format '{{.Size}}' "${IMAGE_REF}")
size_parent=$(docker image inspect --format '{{.Size}}' "${PARENT_REF}")
limit=$(( size_parent * 115 / 100 ))

if (( size_image > limit )); then
  printf "  ✗ size %d > limit %d (parent=%d × 1.15)\n" "${size_image}" "${limit}" "${size_parent}" >&2
  exit 1
fi
printf "  ✓ size %d ≤ limit %d (parent=%d × 1.15)\n" "${size_image}" "${limit}" "${size_parent}"
