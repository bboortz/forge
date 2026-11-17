#!/usr/bin/env bash
# Smoke — /var/lib/apt/lists/ is empty (apt-get update cache cleared).
set -euo pipefail
IMAGE_NAME="${IMAGE_NAME:-go-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

count=$(docker run --rm --entrypoint=/bin/sh "${IMAGE}" \
  -c 'ls /var/lib/apt/lists/ 2>/dev/null | grep -cE "Packages|Release|InRelease" || echo 0' 2>&1 | tail -1 | tr -d '[:space:]')
if [[ "${count}" -gt 0 ]]; then
  echo "  ✗ /var/lib/apt/lists/ still contains ${count} index file(s)" >&2
  exit 1
fi
echo "  ✓ /var/lib/apt/lists/ is empty"
