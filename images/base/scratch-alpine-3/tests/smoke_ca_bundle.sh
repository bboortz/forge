#!/usr/bin/env bash
# Smoke: /etc/ssl/certs/ca-certificates.crt is present + non-empty.
set -euo pipefail

: "${IMAGE_NAME:=base/scratch-alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

# Extract CA bundle from any layer that contains it.
for layer in "${tmp}"/blobs/sha256/*; do
  tar -xf "${layer}" -C "${tmp}" --strip-components=0 etc/ssl/certs/ca-certificates.crt 2>/dev/null \
    && break || true
done

if [[ ! -s "${tmp}/etc/ssl/certs/ca-certificates.crt" ]]; then
  echo "  ✗ /etc/ssl/certs/ca-certificates.crt missing or empty" >&2
  exit 1
fi
size=$(stat -c '%s' "${tmp}/etc/ssl/certs/ca-certificates.crt")
[[ "${size}" -gt 1024 ]] || { echo "  ✗ CA bundle suspiciously small: ${size} bytes" >&2; exit 1; }
echo "  ✓ CA bundle present (${size} bytes)"
