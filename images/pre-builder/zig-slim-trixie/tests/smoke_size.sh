#!/usr/bin/env bash
# Smoke — image size ≤ debian-slim-trixie base × 6.0.
# Unlike other pre-builders (which are a thin apt-upgrade on top of an
# already-complete language upstream), zig-slim-trixie installs the Zig
# toolchain on top of plain Debian. Zig 0.17's x86_64-linux tarball is
# ~325 MB uncompressed (toolchain + stdlib + lld + libc headers for all
# cross-compile targets Zig supports). Budget captures Debian ~82 MB +
# Zig ~325 MB + headroom for future minor bumps.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-zig-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
BUDGET_RATIO_NUM="${BUDGET_RATIO_NUM:-60}"
BUDGET_RATIO_DEN="${BUDGET_RATIO_DEN:-10}"

# BASE is debian-slim-trixie (resolved by the Dockerfile's ARG DEBIAN_SLIM_REF
# default), which the build driver supplies via --build-arg. For the size
# comparison, inspect whichever tag is locally available (forge-local or
# ghcr.io/bboortz).
BASE_LOCAL="forge-local/debian-slim-trixie:latest"
BASE_GHCR="ghcr.io/bboortz/debian-slim-trixie:latest"
if docker image inspect "${BASE_LOCAL}" >/dev/null 2>&1; then
  BASE="${BASE_LOCAL}"
elif docker image inspect "${BASE_GHCR}" >/dev/null 2>&1; then
  BASE="${BASE_GHCR}"
else
  docker pull "${BASE_GHCR}" >/dev/null
  BASE="${BASE_GHCR}"
fi

docker image inspect "${IMAGE}" >/dev/null 2>&1 \
  || { echo "  ✗ ${IMAGE} not present — run make build first" >&2; exit 1; }

BASE_SIZE=$(docker image inspect --format='{{.Size}}' "${BASE}")
OUR_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE}")
BUDGET=$(( BASE_SIZE * BUDGET_RATIO_NUM / BUDGET_RATIO_DEN ))

if [[ "${OUR_SIZE}" -gt "${BUDGET}" ]]; then
  echo "  ✗ size ${OUR_SIZE} exceeds budget ${BUDGET} (base ${BASE_SIZE} × ${BUDGET_RATIO_NUM}/${BUDGET_RATIO_DEN})" >&2
  exit 1
fi
echo "  ✓ size ${OUR_SIZE}B ≤ budget ${BUDGET}B (base ${BASE} = ${BASE_SIZE}B × ${BUDGET_RATIO_NUM}/${BUDGET_RATIO_DEN})"
