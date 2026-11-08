#!/usr/bin/env bash
# Scratch size smoke: 5 MB hard ceiling. hc is ~400 KB, sleep + libc +
# ld-linux ~2.5 MB. Actual builds measure ~3.5 MB.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-5000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-2}"
export REGISTRY="${REGISTRY:-forge-local}"

# scratch-based images have no meaningful "FROM scratch" base, so we skip
# the base × 1.1 budget entirely — the absolute ceiling is the only check.
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
docker image inspect "${IMAGE}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE} not present — run make build first" >&2; exit 1; }
OUR_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE}")
if [[ "${OUR_SIZE}" -gt "${SIZE_CEILING}" ]]; then
  echo "  ✗ size ${OUR_SIZE}B exceeds absolute ceiling ${SIZE_CEILING}B" >&2
  exit 1
fi
echo "  ✓ size ${OUR_SIZE}B ≤ ceiling ${SIZE_CEILING}B"
