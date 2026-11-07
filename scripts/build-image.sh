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

# FG-012: externally-sourced images carry their Dockerfile in an upstream repo.
# For Forge-local images, we still require a local Dockerfile here.
if image_yaml_has_source "${SRC}/image.yaml"; then
  test ! -e "${SRC}/Dockerfile" \
    || { echo "${SRC}: has both source: and Dockerfile (mutually exclusive — see FG-012)" >&2; exit 1; }
else
  test -f "${SRC}/Dockerfile"   || { echo "${SRC}/Dockerfile missing" >&2; exit 1; }
fi

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

# FG-012: resolve the build context + Dockerfile. For Forge-local images,
# both live under images/<dir>/ (current behavior). For externally-sourced
# images, clone the upstream repo at the pinned ref and build there.
BUILD_CONTEXT="${SRC}"
BUILD_DOCKERFILE="${SRC}/Dockerfile"
RESOLVED_SHA="${GIT_SHA}"
CLONE_DIR=""

if image_yaml_has_source "${SRC}/image.yaml"; then
  SRC_GIT=$(image_yaml_source_git "${SRC}/image.yaml")
  SRC_REF=$(image_yaml_source_ref "${SRC}/image.yaml")
  SRC_DOCKERFILE=$(image_yaml_source_dockerfile "${SRC}/image.yaml")
  SRC_CONTEXT=$(image_yaml_source_context "${SRC}/image.yaml")
  [[ -n "${SRC_REF}" ]] || { echo "${SRC}/image.yaml: source.ref is empty" >&2; exit 1; }

  CLONE_DIR=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${CLONE_DIR}'" EXIT
  echo "→ cloning ${SRC_GIT} @ ${SRC_REF}"

  # Try shallow fetch-by-ref first (works for SHAs reachable from tips, tags,
  # branches, and the `latest` keyword which resolves to HEAD). Fall back to
  # a full clone + checkout when the server rejects fetch-by-sha for commits
  # not on an advertised ref.
  if [[ "${SRC_REF}" == "latest" ]]; then
    git -C "${CLONE_DIR}" init -q
    git -C "${CLONE_DIR}" remote add origin "${SRC_GIT}"
    git -C "${CLONE_DIR}" fetch -q --depth=1 origin HEAD
    git -C "${CLONE_DIR}" checkout -q FETCH_HEAD
  else
    git -C "${CLONE_DIR}" init -q
    git -C "${CLONE_DIR}" remote add origin "${SRC_GIT}"
    if git -C "${CLONE_DIR}" fetch -q --depth=1 origin "${SRC_REF}" 2>/dev/null; then
      git -C "${CLONE_DIR}" checkout -q FETCH_HEAD
    else
      echo "  (shallow fetch rejected; falling back to full clone)"
      rm -rf "${CLONE_DIR}"
      CLONE_DIR=$(mktemp -d)
      # shellcheck disable=SC2064
      trap "rm -rf '${CLONE_DIR}'" EXIT
      git clone -q "${SRC_GIT}" "${CLONE_DIR}"
      git -C "${CLONE_DIR}" checkout -q "${SRC_REF}"
    fi
  fi

  RESOLVED_SHA=$(git -C "${CLONE_DIR}" rev-parse HEAD)
  BUILD_CONTEXT="${CLONE_DIR}/${SRC_CONTEXT}"
  BUILD_DOCKERFILE="${CLONE_DIR}/${SRC_DOCKERFILE}"

  test -d "${BUILD_CONTEXT}"     || { echo "source.context '${SRC_CONTEXT}' not found in clone" >&2; exit 1; }
  test -f "${BUILD_DOCKERFILE}"  || { echo "source.dockerfile '${SRC_DOCKERFILE}' not found in clone" >&2; exit 1; }
  echo "→ resolved ${SRC_REF} to ${RESOLVED_SHA}"
fi

# FG-012: for externally-sourced images, inject OCI labels via --label so
# the resolved sha + upstream repo end up on the image even when the
# upstream Dockerfile doesn't declare them. Forge-local Dockerfiles
# already set these via their own LABEL directives — --label would just
# override with the same value.
EXTRA_LABELS=()
if [[ -n "${CLONE_DIR}" ]]; then
  EXTRA_LABELS+=(--label "org.opencontainers.image.revision=${RESOLVED_SHA}")
  EXTRA_LABELS+=(--label "org.opencontainers.image.source=${SRC_GIT}")
  EXTRA_LABELS+=(--label "org.opencontainers.image.created=${BUILD_TIMESTAMP}")
fi

# FG-021: resolve per-image buildx cache args from env. The CI workflows set
# FORGE_CACHE_FROM_PREFIX (ghcr.io/bboortz) + FORGE_CACHE_PUSH (0 on PRs, 1
# on push-to-dev + nightly + build). Script derives per-image :buildcache
# tags so the CI YAML doesn't need per-image knowledge.
BUILDX_CACHE_FROM="${BUILDX_CACHE_FROM:-}"
BUILDX_CACHE_TO="${BUILDX_CACHE_TO:-}"
if [[ -z "${BUILDX_CACHE_FROM}" && -n "${FORGE_CACHE_FROM_PREFIX:-}" ]]; then
  BUILDX_CACHE_FROM="type=registry,ref=${FORGE_CACHE_FROM_PREFIX}/${REPO}:buildcache"
fi
if [[ -z "${BUILDX_CACHE_TO}" && -n "${FORGE_CACHE_FROM_PREFIX:-}" && "${FORGE_CACHE_PUSH:-0}" == "1" ]]; then
  BUILDX_CACHE_TO="type=registry,ref=${FORGE_CACHE_FROM_PREFIX}/${REPO}:buildcache,mode=max"
fi

BUILD_CMD=(docker build)
CACHE_ARGS=()
if [[ -n "${BUILDX_CACHE_FROM}${BUILDX_CACHE_TO}" ]]; then
  BUILD_CMD=(docker buildx build --load)
  [[ -n "${BUILDX_CACHE_FROM}" ]] && CACHE_ARGS+=("--cache-from=${BUILDX_CACHE_FROM}")
  [[ -n "${BUILDX_CACHE_TO}" ]]   && CACHE_ARGS+=("--cache-to=${BUILDX_CACHE_TO}")
  echo "→ buildx cache: from=${BUILDX_CACHE_FROM:-<none>} to=${BUILDX_CACHE_TO:-<none>}"
fi

echo "→ ${BUILD_CMD[*]} ${IMAGE_REF} (dockerfile=${BUILD_DOCKERFILE}, context=${BUILD_CONTEXT}, revision=${RESOLVED_SHA})"
"${BUILD_CMD[@]}" \
  ${PULL_FLAG} \
  --build-arg GIT_SHA="${RESOLVED_SHA}" \
  --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
  --build-arg SCRATCH_BASE_REF="${SCRATCH_BASE_REF}" \
  "${EXTRA_LABELS[@]}" \
  "${CACHE_ARGS[@]}" \
  --file "${BUILD_DOCKERFILE}" \
  --tag "${IMAGE_REF}" \
  "${BUILD_CONTEXT}"
