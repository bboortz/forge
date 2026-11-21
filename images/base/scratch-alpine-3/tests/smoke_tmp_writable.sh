#!/usr/bin/env bash
# Smoke: /tmp is 1777 (world-writable + sticky).
set -euo pipefail

: "${IMAGE_NAME:=base/scratch-alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

for layer in "${tmp}"/blobs/sha256/*; do
  tar tvf "${layer}" 2>/dev/null | grep -E 'tmp/?$' | head -1 \
    | awk '{print $1}' > "${tmp}/tmp_mode" && [[ -s "${tmp}/tmp_mode" ]] && break || true
done

mode=$(cat "${tmp}/tmp_mode" 2>/dev/null || echo "")
# tar v-prefix for dir with sticky+world-writable: drwxrwxrwt
case "${mode}" in
  drwxrwxrwt|drwxrwxrwt*) echo "  ✓ /tmp is 1777 (sticky + world-writable)" ;;
  *) echo "  ✗ /tmp mode is '${mode}', want 'drwxrwxrwt' (1777)" >&2; exit 1 ;;
esac
