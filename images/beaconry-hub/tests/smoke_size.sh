#!/usr/bin/env bash
# Hub image size ≤ 350 MB hard ceiling.
#
# Delivers: FG-014 Scenario "hub stays within its size budget".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-hub}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CEILING_B=$((350 * 1024 * 1024))

size=$(docker image inspect "${IMAGE}" --format '{{.Size}}')
if [[ ${size} -gt ${CEILING_B} ]]; then
  echo "  ✗ size ${size}B exceeds ceiling ${CEILING_B}B (350 MB)" >&2
  exit 1
fi
echo "  ✓ size ${size}B ≤ ceiling ${CEILING_B}B (350 MB)"
