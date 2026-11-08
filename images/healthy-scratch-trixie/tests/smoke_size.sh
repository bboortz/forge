#!/usr/bin/env bash
# Scratch size smoke: 1 MB hard ceiling. hc is ~400 KB + /sbom.json.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-1000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-2}"
export REGISTRY="${REGISTRY:-forge-local}"

IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
docker image inspect "${IMAGE}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE} not present — run make build first" >&2; exit 1; }
OUR_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE}")
if [[ "${OUR_SIZE}" -gt "${SIZE_CEILING}" ]]; then
  echo "  ✗ size ${OUR_SIZE}B exceeds absolute ceiling ${SIZE_CEILING}B" >&2
  exit 1
fi
echo "  ✓ size ${OUR_SIZE}B ≤ ceiling ${SIZE_CEILING}B"
