#!/usr/bin/env bash
# Smoke: /var/cache/pacman/pkg + /var/lib/pacman/sync are empty
# (-Scc + rm kept package indexes out).
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

count=$(docker run --rm "${IMAGE}" bash -c "find /var/cache/pacman/pkg /var/lib/pacman/sync -type f 2>/dev/null | wc -l")
[[ "${count}" -eq 0 ]] || { echo "  ✗ pacman caches have ${count} file(s)" >&2; exit 1; }
echo "  ✓ pacman caches empty"
