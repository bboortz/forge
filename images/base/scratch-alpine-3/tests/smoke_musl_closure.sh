#!/usr/bin/env bash
# Smoke: /lib/ld-musl-x86_64.so.1 + /lib/libc.musl-x86_64.so.1 present.
# Scratch overlays have no shell — inspect via `docker save` tar.
set -euo pipefail

: "${IMAGE_NAME:=base/scratch-alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

paths="${tmp}/paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths}"

for req in \
  "lib/ld-musl-x86_64.so.1" \
  "lib/libc.musl-x86_64.so.1"; do
  grep -qE "(^|/)${req}\$" "${paths}" \
    || fail=$((${fail:-0} + 1))
  grep -qE "(^|/)${req}\$" "${paths}" \
    || echo "  ✗ missing: ${req}" >&2
done

if [[ "${fail:-0}" -gt 0 ]]; then
  echo "  ✗ musl closure incomplete (${fail} missing)" >&2
  exit 1
fi
echo "  ✓ musl loader + libc present"
