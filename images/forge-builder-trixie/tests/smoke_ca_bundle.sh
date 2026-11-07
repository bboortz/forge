#!/usr/bin/env bash
# Smoke: forge-builder-trixie has a usable CA bundle at the standard path.

set -euo pipefail
: "${IMAGE_NAME:=forge-builder-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE_REF}: /etc/ssl/certs/ca-certificates.crt present"
docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -s /etc/ssl/certs/ca-certificates.crt
echo "  ✓ CA bundle present"

echo "→ ${IMAGE_REF}: /var/lib/apt/lists/ carries no Packages/Release files"
# apt leaves empty auxfiles/, partial/ dirs after rm -rf — harmless. We only
# need to assert the actual cache files are gone.
pkgs=$(docker run --rm --entrypoint=/usr/bin/find "${IMAGE_REF}" \
  /var/lib/apt/lists -type f 2>&1 | grep -E "(Packages|Release|InRelease)" || true)
if [[ -n "${pkgs}" ]]; then
  echo "  ✗ apt package indexes still present:" >&2
  echo "${pkgs}" >&2
  exit 1
fi
echo "  ✓ apt package indexes cleaned"
