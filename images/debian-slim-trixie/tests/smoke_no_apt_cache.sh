#!/usr/bin/env bash
# Smoke: /var/lib/apt/lists/ carries no Packages/Release files.
set -euo pipefail
: "${IMAGE_NAME:=debian-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/usr/bin/find "${IMAGE_REF}" /var/lib/apt/lists -type f 2>/dev/null || true)
if [[ -n "${out}" ]]; then
  echo "  ✗ /var/lib/apt/lists/ contains files — cleanup missed" >&2
  echo "${out}" >&2
  exit 1
fi
echo "  ✓ /var/lib/apt/lists/ clean"
