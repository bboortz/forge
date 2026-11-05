#!/usr/bin/env bash
# Scout image size ≤ 150 MB hard ceiling. python-scratch base is ~45 MB;
# scout overlay (syft + python deps + app) adds the rest.
#
# Delivers: FG-012 Scenario "scout stays within its size budget".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-scout}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CEILING_B=$((150 * 1024 * 1024))

size=$(docker image inspect "${IMAGE}" --format '{{.Size}}')
if [[ ${size} -gt ${CEILING_B} ]]; then
  echo "  ✗ size ${size}B exceeds ceiling ${CEILING_B}B (150 MB)" >&2
  exit 1
fi
echo "  ✓ size ${size}B ≤ ceiling ${CEILING_B}B (150 MB)"
