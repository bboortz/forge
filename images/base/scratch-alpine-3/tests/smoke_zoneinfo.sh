#!/usr/bin/env bash
# Smoke: /usr/share/zoneinfo/UTC is present.
set -euo pipefail

: "${IMAGE_NAME:=base/scratch-alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

found=0
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null | grep -qE '(^|/)usr/share/zoneinfo/UTC$' && { found=1; break; } || true
done
[[ "${found}" -eq 1 ]] || { echo "  ✗ /usr/share/zoneinfo/UTC not present" >&2; exit 1; }
echo "  ✓ /usr/share/zoneinfo/UTC present"
