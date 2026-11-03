#!/usr/bin/env bash
# Smoke — final image size ≤ upstream base × 1.1 (10% headroom for apt-upgrade
# deltas). The base is parsed from the Dockerfile's FROM line so the
# comparison tracks any future base-image bump without script edits.
#
# Delivers: FG-002 Scenario "Image size is within budget (base × 1.1)".
# Reusable pattern — every future image's smoke_size.sh uses the same shape.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
DOCKERFILE="images/${IMAGE_NAME}/Dockerfile"

BASE=$(awk 'toupper($1) == "FROM" && $2 !~ /^scratch$/ { print $2; exit }' "${DOCKERFILE}")
if [[ -z "${BASE}" ]]; then
  echo "  ✗ could not parse FROM reference from ${DOCKERFILE}" >&2
  exit 1
fi

docker image inspect "${BASE}"  >/dev/null 2>&1 || docker pull  "${BASE}"  >/dev/null
docker image inspect "${IMAGE}" >/dev/null 2>&1 || { echo "  ✗ ${IMAGE} not present — run make build first" >&2; exit 1; }

BASE_SIZE=$(docker image inspect --format='{{.Size}}' "${BASE}")
OUR_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE}")
BUDGET=$(( BASE_SIZE * 11 / 10 ))

if [[ "${OUR_SIZE}" -gt "${BUDGET}" ]]; then
  echo "  ✗ size ${OUR_SIZE} exceeds budget ${BUDGET} (base ${BASE_SIZE} × 1.1)" >&2
  exit 1
fi
echo "  ✓ size ${OUR_SIZE}B ≤ budget ${BUDGET}B (base ${BASE} = ${BASE_SIZE}B × 1.1)"
