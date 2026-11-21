#!/usr/bin/env bash
# Smoke: /sbom.json is present + non-trivial (CycloneDX with ≥1 component).
set -euo pipefail

: "${IMAGE_NAME:=psitransfer-slim-trixie}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE}" -e "
const fs = require('fs');
try {
  const s = JSON.parse(fs.readFileSync('/sbom.json', 'utf8'));
  process.stdout.write(JSON.stringify({components: (s.components || []).length, format: s.bomFormat || '?'}));
} catch (e) {
  process.stdout.write('error:' + e.message);
}")
echo "  SBOM: ${out}"
[[ "${out}" == *'"format":"CycloneDX"'* ]] \
  || { echo "  ✗ /sbom.json not CycloneDX: ${out}" >&2; exit 1; }
echo "${out}" | grep -qE '"components":[1-9]' \
  || { echo "  ✗ /sbom.json has zero components: ${out}" >&2; exit 1; }
echo "  ✓ CycloneDX SBOM embedded"
