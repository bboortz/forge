#!/usr/bin/env bash
# Smoke — final image size ≤ upstream base × 1.3 (30% headroom for
# sid's rolling-release apt-upgrade delta — can be chunkier than trixie).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-pre-builder/debian-slim-sid}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
BUDGET_RATIO_NUM="${BUDGET_RATIO_NUM:-13}"
BUDGET_RATIO_DEN="${BUDGET_RATIO_DEN:-10}"

DOCKERFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Dockerfile"
BASE=$(awk 'toupper($1) == "FROM" && $2 !~ /^scratch$/ { print $2 }' "${DOCKERFILE}" | tail -1 | awk '{print $1}')
if [[ -z "${BASE}" ]]; then
  echo "  ✗ could not parse FROM reference from ${DOCKERFILE}" >&2
  exit 1
fi

docker image inspect "${BASE}"  >/dev/null 2>&1 || docker pull  "${BASE}"  >/dev/null
docker image inspect "${IMAGE}" >/dev/null 2>&1 || { echo "  ✗ ${IMAGE} not present — run make build first" >&2; exit 1; }

BASE_SIZE=$(docker image inspect --format='{{.Size}}' "${BASE}")
OUR_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE}")
BUDGET=$(( BASE_SIZE * BUDGET_RATIO_NUM / BUDGET_RATIO_DEN ))

if [[ "${OUR_SIZE}" -gt "${BUDGET}" ]]; then
  echo "  ✗ size ${OUR_SIZE} exceeds budget ${BUDGET} (base ${BASE_SIZE} × ${BUDGET_RATIO_NUM}/${BUDGET_RATIO_DEN})" >&2
  exit 1
fi
echo "  ✓ size ${OUR_SIZE}B ≤ budget ${BUDGET}B (base ${BASE} = ${BASE_SIZE}B × ${BUDGET_RATIO_NUM}/${BUDGET_RATIO_DEN})"
