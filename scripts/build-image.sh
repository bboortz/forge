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

# FG-025: forge-builder-trixie is a builder-stage dependency, not a scratch_base
# COPY-from dependency. It's not listed in image.yaml depends_on (to preserve
# the current CI publish ordering model), but it must exist locally before any
# scratch-image build. Build it on demand if any scratch image is being built.
_FORGE_BUILDER_DIR="${ROOT}/images/forge-builder-trixie"
case "${IMAGE_DIR}" in
  forge-builder-trixie|python-slim-trixie|beaconry-telegram-mock|beaconry-hub|beaconry-scout|forge-builder-go-trixie)
    _needs_forge_builder=0 ;;
  *)
    _needs_forge_builder=1 ;;
esac
if [[ "${_needs_forge_builder}" == "1" && -d "${_FORGE_BUILDER_DIR}" ]]; then
  echo "→ builder-stage dependency: forge-builder-trixie"
  REGISTRY="${REGISTRY}" "${BASH_SOURCE[0]}" forge-builder-trixie
fi

# FG-046: forge-builder-go-trixie is a builder-stage dependency for every
# from-Go-source image. Same pattern as forge-builder-trixie above.
# Auto-build on demand when the current image's Dockerfile declares
# FORGE_BUILDER_GO_REF.
_FORGE_BUILDER_GO_DIR="${ROOT}/images/forge-builder-go-trixie"
if [[ -d "${_FORGE_BUILDER_GO_DIR}" && -f "${SRC}/Dockerfile" ]] \
   && grep -q "FORGE_BUILDER_GO_REF" "${SRC}/Dockerfile"; then
  echo "→ builder-stage dependency: forge-builder-go-trixie"
  REGISTRY="${REGISTRY}" "${BASH_SOURCE[0]}" forge-builder-go-trixie
fi

REPO=$(image_yaml_repo "${SRC}/image.yaml")
TAG=$(image_yaml_get   "${SRC}/image.yaml" tag)
[[ -n "${TAG}" ]] || { echo "${SRC}/image.yaml missing required 'tag:' field" >&2; exit 1; }
IMAGE_REF="${REGISTRY}/${REPO}:${TAG}"

# FG-023: stamp-skip. Before computing the rest of the build environment,
# ask whether the inputs to this image's build have changed since the last
# successful run on this runner. If not AND the tag still exists in the
# daemon, skip docker build entirely. Daily cron (build.yml) ignores
# stamps because it does not route through this script's skip path.
STAMP_FILE="${ROOT}/.make/stamps/${IMAGE_DIR}.stamp"
if [[ "${FORGE_NO_SKIP:-0}" != "1" && -f "${STAMP_FILE}" ]]; then
  _OLD_STAMP=$(cat "${STAMP_FILE}")
  _NEW_STAMP=$(bash "${ROOT}/scripts/stamp-image.sh" "${IMAGE_DIR}")
  if [[ "${_OLD_STAMP}" == "${_NEW_STAMP}" ]] \
     && docker image inspect "${IMAGE_REF}" >/dev/null 2>&1; then
    echo "→ stamp-skip: ${IMAGE_REF} (inputs unchanged, tag present in daemon)"
    exit 0
  fi
fi

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

# FG-025: resolve FORGE_BUILDER_REF the same way — prefer the local tag if
# present (we just built it above), else fall back to GHCR.
_BUILDER_YAML="${ROOT}/images/forge-builder-trixie/image.yaml"
if [[ -f "${_BUILDER_YAML}" ]]; then
  _BUILDER_TAG=$(image_yaml_get "${_BUILDER_YAML}" tag)
else
  _BUILDER_TAG="latest"
fi
FORGE_BUILDER_REF="${REGISTRY}/forge-builder-trixie:${_BUILDER_TAG}"
if ! docker image inspect "${FORGE_BUILDER_REF}" >/dev/null 2>&1; then
  FORGE_BUILDER_REF="ghcr.io/bboortz/forge-builder-trixie:${_BUILDER_TAG}"
fi

# FG-046: same for FORGE_BUILDER_GO_REF.
_BUILDER_GO_YAML="${ROOT}/images/forge-builder-go-trixie/image.yaml"
if [[ -f "${_BUILDER_GO_YAML}" ]]; then
  _BUILDER_GO_TAG=$(image_yaml_get "${_BUILDER_GO_YAML}" tag)
else
  _BUILDER_GO_TAG="latest"
fi
FORGE_BUILDER_GO_REF="${REGISTRY}/forge-builder-go-trixie:${_BUILDER_GO_TAG}"
if ! docker image inspect "${FORGE_BUILDER_GO_REF}" >/dev/null 2>&1; then
  FORGE_BUILDER_GO_REF="ghcr.io/bboortz/forge-builder-go-trixie:${_BUILDER_GO_TAG}"
fi

# FG-031: resolve HC_REF the same way for images whose Dockerfile declares
# ARG HC_REF (healthy-scratch-trixie + any image embedding /hc per FG-031).
# Prefer forge-local/hc:0.1.0 if present (set up for local dev); else fall
# back to the upstream published image ghcr.io/bboortz/hc:0.1.0.
HC_REF="${REGISTRY}/hc:0.1.0"
if ! docker image inspect "${HC_REF}" >/dev/null 2>&1; then
  HC_REF="ghcr.io/bboortz/hc:0.1.0"
fi

PULL_FLAG="--pull"
# Drop --pull if either referenced base is a daemon-only forge-local tag —
# docker build --pull tries to resolve it from a registry and aborts with
# "pull access denied" because forge-local isn't a real registry.
if docker image inspect "${SCRATCH_BASE_REF}" >/dev/null 2>&1; then
  PULL_FLAG=""
else
  SCRATCH_BASE_REF="ghcr.io/bboortz/scratch-base-trixie:latest"
fi
# FG-025: same guard for FORGE_BUILDER_REF. When it's forge-local/... we must
# drop --pull regardless of SCRATCH_BASE_REF.
if [[ "${FORGE_BUILDER_REF}" == forge-local/* ]]; then
  PULL_FLAG=""
fi
# FG-046: same guard for FORGE_BUILDER_GO_REF.
if [[ "${FORGE_BUILDER_GO_REF}" == forge-local/* ]]; then
  PULL_FLAG=""
fi
# FG-031: same guard for HC_REF — forge-local/hc:0.1.0 isn't a real registry.
if [[ "${HC_REF}" == forge-local/* ]]; then
  PULL_FLAG=""
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

# FG-021 / FG-025: buildx's docker-container driver can't resolve
# `FROM forge-local/...` references (daemon-only, not reachable from the
# builder container). Fall back to classic docker build if ANY FROM
# reference this image will use resolves to a forge-local tag:
#   - SCRATCH_BASE_REF for scratch derivatives (FG-021)
#   - FORGE_BUILDER_REF for images whose builder stage FROMs forge-builder-trixie (FG-025)
_HAS_LOCAL_DEP=0
if [[ "${SCRATCH_BASE_REF}" == forge-local/* ]] \
   && image_yaml_depends "${SRC}/image.yaml" | grep -q .; then
  _HAS_LOCAL_DEP=1
fi
# FG-025: check Dockerfile actually references the forge-builder FROM. Only
# images whose Dockerfile declares ARG FORGE_BUILDER_REF trigger this.
if [[ "${_HAS_LOCAL_DEP}" == "0" && "${FORGE_BUILDER_REF}" == forge-local/* ]] \
   && [[ -f "${BUILD_DOCKERFILE}" ]] \
   && grep -q "FORGE_BUILDER_REF" "${BUILD_DOCKERFILE}"; then
  _HAS_LOCAL_DEP=1
fi
# FG-046: same for FORGE_BUILDER_GO_REF.
if [[ "${_HAS_LOCAL_DEP}" == "0" && "${FORGE_BUILDER_GO_REF}" == forge-local/* ]] \
   && [[ -f "${BUILD_DOCKERFILE}" ]] \
   && grep -q "FORGE_BUILDER_GO_REF" "${BUILD_DOCKERFILE}"; then
  _HAS_LOCAL_DEP=1
fi
# FG-031: same check for HC_REF.
if [[ "${_HAS_LOCAL_DEP}" == "0" && "${HC_REF}" == forge-local/* ]] \
   && [[ -f "${BUILD_DOCKERFILE}" ]] \
   && grep -q "HC_REF" "${BUILD_DOCKERFILE}"; then
  _HAS_LOCAL_DEP=1
fi

BUILD_CMD=(docker build)
CACHE_ARGS=()
if [[ -n "${BUILDX_CACHE_FROM}${BUILDX_CACHE_TO}" && "${_HAS_LOCAL_DEP}" == "0" ]]; then
  BUILD_CMD=(docker buildx build --load)
  [[ -n "${BUILDX_CACHE_FROM}" ]] && CACHE_ARGS+=("--cache-from=${BUILDX_CACHE_FROM}")
  [[ -n "${BUILDX_CACHE_TO}" ]]   && CACHE_ARGS+=("--cache-to=${BUILDX_CACHE_TO}")
  echo "→ buildx cache: from=${BUILDX_CACHE_FROM:-<none>} to=${BUILDX_CACHE_TO:-<none>}"
elif [[ -n "${BUILDX_CACHE_FROM}${BUILDX_CACHE_TO}" ]]; then
  echo "→ local base (SCRATCH_BASE_REF=${SCRATCH_BASE_REF}, FORGE_BUILDER_REF=${FORGE_BUILDER_REF}): skipping buildx cache (daemon-only FROM)"
fi

echo "→ ${BUILD_CMD[*]} ${IMAGE_REF} (dockerfile=${BUILD_DOCKERFILE}, context=${BUILD_CONTEXT}, revision=${RESOLVED_SHA})"
"${BUILD_CMD[@]}" \
  ${PULL_FLAG} \
  --build-arg GIT_SHA="${RESOLVED_SHA}" \
  --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
  --build-arg SCRATCH_BASE_REF="${SCRATCH_BASE_REF}" \
  --build-arg FORGE_BUILDER_REF="${FORGE_BUILDER_REF}" \
  --build-arg FORGE_BUILDER_GO_REF="${FORGE_BUILDER_GO_REF}" \
  --build-arg HC_REF="${HC_REF}" \
  "${EXTRA_LABELS[@]}" \
  "${CACHE_ARGS[@]}" \
  --file "${BUILD_DOCKERFILE}" \
  --tag "${IMAGE_REF}" \
  "${BUILD_CONTEXT}"

# FG-023: record stamp of the inputs that produced this image so a
# subsequent invocation with identical inputs can skip docker build.
mkdir -p "${ROOT}/.make/stamps"
bash "${ROOT}/scripts/stamp-image.sh" "${IMAGE_DIR}" > "${STAMP_FILE}"
