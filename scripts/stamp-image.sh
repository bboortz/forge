#!/usr/bin/env bash
# FG-023: compute a deterministic stamp for an image dir.
# A stamp is a single SHA-256 over all inputs that affect the built image:
#   1. Tracked + working-tree content under images/<dir>/
#   2. Resolved upstream FROM digest (so a tag-mutation invalidates the stamp)
#   3. Baseline image ID for scratch derivatives (transitive invalidation)
#   4. Resolved external SHA for FG-012 externally-sourced images
#
# Usage: scripts/stamp-image.sh <image-dir>
#        FAKE_FROM_DIGEST=... scripts/stamp-image.sh <image-dir>  # test override

set -euo pipefail

IMAGE_DIR="${1:?usage: $0 <image-dir>}"
ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

# shellcheck source=scripts/_image_yaml.sh disable=SC1091
. "${ROOT}/scripts/_image_yaml.sh"

SRC="images/${IMAGE_DIR}"
test -d "${SRC}"                || { echo "no such image dir: ${SRC}" >&2; exit 1; }
test -f "${SRC}/image.yaml"     || { echo "${SRC}/image.yaml missing" >&2; exit 1; }

# --- 1. hash the image dir (tracked + modified working-tree files) -----------
# git ls-files -s gives us <mode> <sha> <stage> <path>. For an unmodified
# tracked file, the sha is accurate. For a modified file, we need the
# working-tree hash. We detect modifications via `git diff --name-only`.
_dir_hash() {
  local tmp
  tmp=$(mktemp)
  # tracked files
  git ls-files -s -- "${SRC}" | awk '{print $2, $4}' | sort -k2 > "${tmp}.tracked"
  # modified or untracked files under SRC — hash their current working-tree content
  {
    git diff --name-only -- "${SRC}"
    git ls-files --others --exclude-standard -- "${SRC}"
  } | sort -u | while read -r path; do
    if [[ -f "${path}" ]]; then
      printf '%s %s\n' "$(git hash-object "${path}")" "${path}"
    fi
  done > "${tmp}.working"
  # merge: working-tree hashes override tracked hashes for modified paths
  awk 'NR==FNR { modified[$2]=$1; next } { if (!($2 in modified)) print $1, $2 }' \
    "${tmp}.working" "${tmp}.tracked" \
    | cat - "${tmp}.working" \
    | sort -k2 \
    | sha256sum | cut -d' ' -f1
  rm -f "${tmp}" "${tmp}.tracked" "${tmp}.working"
}

DIR_HASH=$(_dir_hash)

# --- 2. resolve upstream FROM digest -----------------------------------------
_from_digest() {
  if [[ -n "${FAKE_FROM_DIGEST:-}" ]]; then
    printf '%s' "${FAKE_FROM_DIGEST}"
    return 0
  fi
  # Prefer the Dockerfile's FIRST FROM (stage 0). Strip ARG defaults and
  # comments. Skip FROMs that refer to prior stages or to ${SCRATCH_BASE_REF}
  # (resolved separately via baseline image ID).
  local dockerfile="${SRC}/Dockerfile"
  if [[ ! -f "${dockerfile}" ]]; then
    # Externally-sourced images don't have a local Dockerfile — use the
    # upstream repo's resolved sha as the "digest" proxy (see § 4 below).
    printf '%s' "external"
    return 0
  fi
  local from_ref
  from_ref=$(awk '/^FROM[[:space:]]/{
    ref=$2
    # Strip ARG default like ${BASE:-python:3.13-slim-trixie}
    sub(/^\$\{[^:}]*:-/, "", ref)
    sub(/\}$/, "", ref)
    # Skip prior-stage references
    if (ref ~ /^[a-z_][a-z_0-9-]*$/ && ref !~ /:/) next
    # Skip scratch (no upstream to resolve)
    if (ref == "scratch") { print ref; exit }
    # Skip ARG-based baseline (resolved via baseline image ID instead)
    if (ref ~ /SCRATCH_BASE_REF/) next
    print ref; exit
  }' "${dockerfile}")

  if [[ -z "${from_ref}" || "${from_ref}" == "scratch" ]]; then
    printf '%s' "none"
    return 0
  fi

  # Try buildx imagetools first (fast, no pull); fall back to manifest inspect.
  # Both may fail offline — don't gate the stamp on network, degrade gracefully.
  local digest
  digest=$(docker buildx imagetools inspect "${from_ref}" --raw 2>/dev/null \
    | sha256sum | cut -d' ' -f1 || true)
  if [[ -z "${digest}" ]]; then
    digest=$(docker manifest inspect "${from_ref}" 2>/dev/null \
      | sha256sum | cut -d' ' -f1 || true)
  fi
  if [[ -z "${digest}" ]]; then
    # Offline / unreachable registry — use a stable marker so stamp stays
    # consistent until the next online build. Not ideal, but the daily cron
    # (build.yml) is the authoritative publisher and ignores stamps.
    digest="offline"
  fi
  printf '%s' "${digest}"
}

FROM_DIGEST=$(_from_digest)

# --- 3. baseline image ID (scratch derivatives) -----------------------------
_baseline_id() {
  # depends_on resolves to a local baseline image. Use its image ID as the
  # transitive invalidation key. Only applies when the baseline is in daemon.
  local dep baseline_tag baseline_ref id
  dep=$(image_yaml_depends "${SRC}/image.yaml" | head -1)
  [[ -z "${dep}" ]] && { printf '%s' "none"; return 0; }
  baseline_tag=$(image_yaml_get "images/${dep}/image.yaml" tag)
  baseline_ref="forge-local/${dep}:${baseline_tag}"
  id=$(docker image inspect "${baseline_ref}" --format '{{.Id}}' 2>/dev/null || true)
  if [[ -z "${id}" ]]; then
    # Baseline not built locally (yet). Use the dep's own stamp if present —
    # keeps intra-run determinism when stamp exists but daemon tag doesn't.
    local dep_stamp=".make/stamps/${dep}.stamp"
    if [[ -f "${dep_stamp}" ]]; then
      id="stamp:$(cat "${dep_stamp}")"
    else
      id="none"
    fi
  fi
  printf '%s' "${id}"
}

BASELINE_ID=$(_baseline_id)

# --- 4. externally-sourced resolved SHA --------------------------------------
_external_sha() {
  # For FG-012 images, the Dockerfile lives upstream. We resolve the pinned
  # ref to a concrete sha at build time — read source.ref here (either a
  # concrete sha, a branch/tag name, or the keyword "latest"). For the
  # stamp, we need the RESOLVED sha; but resolving requires a clone, which
  # is expensive. Compromise: hash source.ref (literal string); when the
  # ref is "latest" or a branch, the daily cron is the authoritative
  # invalidator via rebuild-ignoring-stamp.
  if ! image_yaml_has_source "${SRC}/image.yaml"; then
    printf '%s' "none"
    return 0
  fi
  local ref
  ref=$(image_yaml_source_ref "${SRC}/image.yaml")
  printf '%s' "${ref}"
}

EXTERNAL_SHA=$(_external_sha)

# --- combine into final stamp ------------------------------------------------
printf '%s|%s|%s|%s' "${DIR_HASH}" "${FROM_DIGEST}" "${BASELINE_ID}" "${EXTERNAL_SHA}" \
  | sha256sum | cut -d' ' -f1
