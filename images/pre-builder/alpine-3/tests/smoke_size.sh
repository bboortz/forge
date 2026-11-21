#!/usr/bin/env bash
# Smoke: image size ≤ upstream alpine:3 × 2.0 (alpine starts so tiny that +CA +dumb-init ~doubles).
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PARENT="alpine:3"

docker image inspect "${IMAGE_REF}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE_REF} not present" >&2; exit 1; }
docker image inspect "${PARENT}" >/dev/null 2>&1 || docker pull "${PARENT}" >/dev/null

size_image=$(docker image inspect --format '{{.Size}}' "${IMAGE_REF}")
size_parent=$(docker image inspect --format '{{.Size}}' "${PARENT}")
limit=$(( size_parent * 200 / 100 ))

if (( size_image > limit )); then
  printf "  ✗ size %d > limit %d (parent=%d × 2.0)\n" "${size_image}" "${limit}" "${size_parent}" >&2
  exit 1
fi
printf "  ✓ size %d ≤ limit %d (parent=%d × 2.0)\n" "${size_image}" "${limit}" "${size_parent}"
