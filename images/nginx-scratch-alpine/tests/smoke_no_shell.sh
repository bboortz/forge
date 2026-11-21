#!/usr/bin/env bash
# Smoke: no /bin/sh or /bin/busybox (scratch runtime shape).
set -euo pipefail

: "${IMAGE_NAME:=nginx-scratch-alpine}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

paths="${tmp}/paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths}"

for forbidden in "bin/sh" "bin/bash" "bin/busybox"; do
  if grep -qE "(^|/)${forbidden}\$" "${paths}"; then
    echo "  ✗ forbidden path present: ${forbidden} (scratch should have no shell)" >&2
    exit 1
  fi
done
echo "  ✓ no shell (scratch runtime shape confirmed)"
