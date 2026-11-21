#!/usr/bin/env bash
# Smoke: image size ≤ upstream archlinux:latest × 1.5 (rolling base; +CA on
# top of ~400 MB archlinux fits within 50% headroom).
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PARENT="archlinux:latest"

docker image inspect "${IMAGE_REF}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE_REF} not present" >&2; exit 1; }
docker image inspect "${PARENT}" >/dev/null 2>&1 || docker pull "${PARENT}" >/dev/null

size_image=$(docker image inspect --format '{{.Size}}' "${IMAGE_REF}")
size_parent=$(docker image inspect --format '{{.Size}}' "${PARENT}")
limit=$(( size_parent * 150 / 100 ))

if (( size_image > limit )); then
  printf "  ✗ size %d > limit %d (parent=%d × 1.5)\n" "${size_image}" "${limit}" "${size_parent}" >&2
  exit 1
fi
printf "  ✓ size %d ≤ limit %d (parent=%d × 1.5)\n" "${size_image}" "${limit}" "${size_parent}"
