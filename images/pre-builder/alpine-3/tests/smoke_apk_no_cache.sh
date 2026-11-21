#!/usr/bin/env bash
# Smoke: /var/cache/apk is empty (--no-cache kept indexes out).
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Alpine's apk --no-cache uses a tmpfs; nothing persists to /var/cache/apk.
count=$(docker run --rm "${IMAGE}" sh -c "find /var/cache/apk -type f 2>/dev/null | wc -l")
[[ "${count}" -eq 0 ]] || { echo "  ✗ /var/cache/apk has ${count} files" >&2; exit 1; }
echo "  ✓ /var/cache/apk is empty"
