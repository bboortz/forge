#!/usr/bin/env bash
# Smoke: /sbom.json present + non-trivial.
set -euo pipefail

: "${IMAGE_NAME:=nginx-scratch-alpine}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

for layer in "${tmp}"/blobs/sha256/*; do
  tar -xf "${layer}" -C "${tmp}" sbom.json 2>/dev/null && break || true
done

[[ -s "${tmp}/sbom.json" ]] || { echo "  ✗ /sbom.json missing or empty" >&2; exit 1; }
# CycloneDX marker
grep -q '"bomFormat":"CycloneDX"' "${tmp}/sbom.json" \
  || { echo "  ✗ /sbom.json not CycloneDX format" >&2; exit 1; }
echo "  ✓ CycloneDX SBOM embedded"
