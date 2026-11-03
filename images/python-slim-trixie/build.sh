#!/usr/bin/env bash
# Build driver for images/python/. Invoked by the top-level Makefile.
# For FG-001: plain `docker build` for linux/amd64. buildx + multi-arch
# arrives with the arm64 story (see docs/plan/IDEAS.md).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

IMAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ docker build ${IMAGE_REF}"
docker build \
  --pull \
  --build-arg GIT_SHA="${GIT_SHA}" \
  --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
  --tag "${IMAGE_REF}" \
  "${IMAGE_DIR}"
