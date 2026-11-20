#!/usr/bin/env bash
# Smoke: apt-upgrade has been applied. Proxy: no package has a pending
# upgrade (`apt list --upgradable` returns only the header line).
set -euo pipefail
: "${IMAGE_NAME:=debian-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/bin/sh "${IMAGE_REF}" -c '
  apt-get update >/dev/null 2>&1
  apt list --upgradable 2>/dev/null | tail -n +2
' 2>&1)

if [[ -n "${out}" ]]; then
  echo "  ✗ apt reports packages still upgradable (image not apt-upgraded?):" >&2
  echo "${out}" | head -5 >&2
  exit 1
fi
echo "  ✓ apt list --upgradable is empty (apt-upgrade applied)"
