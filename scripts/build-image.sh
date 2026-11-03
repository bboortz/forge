#!/usr/bin/env bash
# Central build driver — one entry point for every image under images/.
# Reads images/<image-dir>/image.yaml to resolve the published repo + tag,
# then runs `docker build --pull` with standard labels.
#
# Usage:
#   scripts/build-image.sh <image-dir>
#     e.g. scripts/build-image.sh python-slim-trixie
#
# Env overrides:
#   REGISTRY (default: forge-local; CI sets ghcr.io/bboortz)

set -euo pipefail

IMAGE_DIR="${1:?usage: $0 <image-dir>}"
REGISTRY="${REGISTRY:-forge-local}"
ROOT="$(git rev-parse --show-toplevel)"

# shellcheck source=scripts/_image_yaml.sh
. "${ROOT}/scripts/_image_yaml.sh"

SRC="${ROOT}/images/${IMAGE_DIR}"
test -d "${SRC}"                || { echo "no such image dir: ${SRC}" >&2; exit 1; }
test -f "${SRC}/image.yaml"     || { echo "${SRC}/image.yaml missing" >&2; exit 1; }
test -f "${SRC}/Dockerfile"     || { echo "${SRC}/Dockerfile missing" >&2; exit 1; }

REPO=$(image_yaml_get "${SRC}/image.yaml" repo)
TAG=$(image_yaml_get  "${SRC}/image.yaml" tag)
IMAGE_REF="${REGISTRY}/${REPO}:${TAG}"

GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "→ docker build ${IMAGE_REF} (from images/${IMAGE_DIR}/)"
docker build \
  --pull \
  --build-arg GIT_SHA="${GIT_SHA}" \
  --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
  --tag "${IMAGE_REF}" \
  "${SRC}"
