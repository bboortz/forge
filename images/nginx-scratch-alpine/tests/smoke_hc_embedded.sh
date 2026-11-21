#!/usr/bin/env bash
# Smoke: /hc present + HEALTHCHECK baked.
set -euo pipefail

: "${IMAGE_NAME:=nginx-scratch-alpine}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

hc=$(docker image inspect --format '{{json .Config.Healthcheck}}' "${IMAGE}")
[[ "${hc}" != "null" ]] || { echo "  ✗ no HEALTHCHECK baked" >&2; exit 1; }
echo "${hc}" | grep -q "/hc" || { echo "  ✗ HEALTHCHECK doesn't invoke /hc: ${hc}" >&2; exit 1; }

# Also confirm /hc is in the image via tar inspection (scratch has no shell).
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"
found=0
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null | grep -qE '(^|/)hc$' && { found=1; break; } || true
done
[[ "${found}" -eq 1 ]] || { echo "  ✗ /hc not in any image layer" >&2; exit 1; }
echo "  ✓ /hc present + HEALTHCHECK baked"
