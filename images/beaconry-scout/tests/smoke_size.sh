#!/usr/bin/env bash
# Scout image size ≤ 160 MB hard ceiling. python-scratch base is ~47.5 MB
# post-FG-031 (adds /hc); scout overlay (syft + python deps + app) adds
# the rest. Ceiling bumped 150 → 160 MB in FG-031 to absorb the /hc
# addition in the base without immediately re-tripping.
#
# Delivers: FG-012 Scenario "scout stays within its size budget".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-scout}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CEILING_B=$((160 * 1024 * 1024))

size=$(docker image inspect "${IMAGE}" --format '{{.Size}}')
if [[ ${size} -gt ${CEILING_B} ]]; then
  echo "  ✗ size ${size}B exceeds ceiling ${CEILING_B}B (160 MB)" >&2
  exit 1
fi
echo "  ✓ size ${size}B ≤ ceiling ${CEILING_B}B (160 MB)"
