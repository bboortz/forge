#!/usr/bin/env bash
# Central build driver — one entry point for every image under images/.
# Reads images/<image-dir>/image.yaml to resolve the published repo + tag,
# then runs `docker build --pull` with standard labels.
#
# Usage:
#   scripts/build-image.sh <image-dir>
#     e.g. scripts/build-image.sh python-slim-trixie
#
# Scratch variants that derive from scratch-base-trixie (FG-005) pass
# SCRATCH_BASE_REF as a build-arg pointing at the local baseline image,
# so the Dockerfile's `FROM ${SCRATCH_BASE_REF}` resolves to whatever
# REGISTRY produced (forge-local for local builds; ghcr.io/bboortz in CI).
#
# Env overrides:
#   REGISTRY (default: forge-local; CI sets ghcr.io/bboortz)

set -euo pipefail

IMAGE_DIR="${1:?usage: $0 <image-dir>}"
REGISTRY="${REGISTRY:-forge-local}"
ROOT="$(git rev-parse --show-toplevel)"

# shellcheck source=scripts/_image_yaml.sh disable=SC1091
. "${ROOT}/scripts/_image_yaml.sh"

SRC="${ROOT}/images/${IMAGE_DIR}"
test -d "${SRC}"                || { echo "no such image dir: ${SRC}" >&2; exit 1; }
test -f "${SRC}/image.yaml"     || { echo "${SRC}/image.yaml missing" >&2; exit 1; }
test -f "${SRC}/Dockerfile"     || { echo "${SRC}/Dockerfile missing" >&2; exit 1; }

# Build any depends_on first so derivatives can COPY --from= them locally.
while IFS= read -r dep; do
  [[ -z "${dep}" ]] && continue
  echo "→ dependency: ${dep}"
  REGISTRY="${REGISTRY}" "${BASH_SOURCE[0]}" "${dep}"
done < <(image_yaml_depends "${SRC}/image.yaml")

REPO=$(image_yaml_repo "${SRC}/image.yaml")
TAG=$(image_yaml_get   "${SRC}/image.yaml" tag)
[[ -n "${TAG}" ]] || { echo "${SRC}/image.yaml missing required 'tag:' field" >&2; exit 1; }
IMAGE_REF="${REGISTRY}/${REPO}:${TAG}"

GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Supply SCRATCH_BASE_REF so scratch derivatives build against our locally-
# produced baseline instead of attempting to pull from GHCR. Baseline tag
# is resolved dynamically from images/scratch-base-trixie/image.yaml so
# future bumps (0.1 → 0.2 → …) don't require script edits.
_BASELINE_YAML="${ROOT}/images/scratch-base-trixie/image.yaml"
if [[ -f "${_BASELINE_YAML}" ]]; then
  _BASELINE_TAG=$(image_yaml_get "${_BASELINE_YAML}" tag)
else
  _BASELINE_TAG="latest"
fi
SCRATCH_BASE_REF="${REGISTRY}/scratch-base-trixie:${_BASELINE_TAG}"
PULL_FLAG="--pull"
if docker image inspect "${SCRATCH_BASE_REF}" >/dev/null 2>&1; then
  # Local baseline present; don't --pull or the legacy builder tries to
  # fetch it from the forge-local "registry" which doesn't exist and
  # the build aborts with "pull access denied".
  PULL_FLAG=""
else
  SCRATCH_BASE_REF="ghcr.io/bboortz/scratch-base-trixie:latest"
fi

echo "→ docker build ${IMAGE_REF} (from images/${IMAGE_DIR}/)"
docker build \
  ${PULL_FLAG} \
  --build-arg GIT_SHA="${GIT_SHA}" \
  --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
  --build-arg SCRATCH_BASE_REF="${SCRATCH_BASE_REF}" \
  --tag "${IMAGE_REF}" \
  "${SRC}"
