#!/usr/bin/env bash
# Emit a GHA-matrix JSON listing image dirs. Modes:
#
#   scripts/discover-images.sh              → every image (legacy caller)
#   scripts/discover-images.sh pre-builders → forge-rooted slim bases (FG-042)
#   scripts/discover-images.sh builders     → shared builder-stage images (FG-025, FG-046)
#   scripts/discover-images.sh base         → images with no depends_on + not pre-builder/builder
#   scripts/discover-images.sh derivatives  → images WITH depends_on
#
# FG-057: `--filter <pattern>` scopes the matrix to a subset of images. The
# filter applies AFTER the tier-select, so e.g. `pre-builders --filter prometheus-*`
# correctly returns an empty matrix (prometheus-scratch isn't a pre-builder).
#
#   scripts/discover-images.sh <mode> --filter all           # default (unchanged)
#   scripts/discover-images.sh <mode> --filter <name>        # exact dir match
#   scripts/discover-images.sh <mode> --filter <a>,<b>,<c>   # comma list (union)
#   scripts/discover-images.sh <mode> --filter 'prom-*'      # shell glob
#
# A filter that matches zero images (post-tier-select) is NOT an error — the
# matrix is simply empty, which the GHA job's strategy.matrix handles cleanly.
# A filter whose tokens don't match ANY image dir at all (regardless of tier)
# IS an error — the operator asked for something that doesn't exist.
#
# build.yml uses the four-mode split so pre-builders publish before
# builders publish before scratch-base publishes before derivatives that
# FROM any upstream forge image (FG-005, FG-025, FG-042, FG-046).
#
# Output shape (single line, suitable for GITHUB_OUTPUT):
#   {"include":[{"image_dir":"...","repo":"...","tag":"..."}, ...]}

set -euo pipefail

MODE="${1:-all}"
shift || true

FILTER="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      FILTER="${2:?--filter requires a value}"
      shift 2
      ;;
    --filter=*)
      FILTER="${1#--filter=}"
      shift
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# FG-042 + FG-051 + FG-058: pre-builders — forge-rooted slim bases
# consumed by downstream slim/scratch images. Must publish BEFORE
# forge-builder-python-trixie (dogfood FROMs python-slim-trixie) and
# BEFORE cadvisor-slim / ipmi-exporter-slim (FROM debian-slim-trixie).
# FG-051 adds ubuntu-slim-noble (github-runner-noble FROMs it).
# FG-058 adds debian-slim-sid as an escape-hatch pre-builder for CVEs
# that trixie leaves unfixed but sid patches at the same SONAME.
_PRE_BUILDERS=(pre-builder/debian-slim-trixie pre-builder/debian-slim-sid pre-builder/go-slim-trixie pre-builder/python-slim-trixie pre-builder/ubuntu-slim-noble pre-builder/node-slim-trixie pre-builder/zig-slim-trixie pre-builder/alpine-3 pre-builder/archlinux)

# FG-066: forge mirror tier. Members live under `images/mirror/<name>/`
# and are classified as "mirrors" (new tier) regardless of depends_on
# shape. Published in the new publish-mirrors CI tier (parallel with
# publish-pre-builders). Shape enforced by verify-dockerfile-
# conformance.py Rule 10 (zero-mod).
_is_mirror() {
  local name="$1"
  [[ "${name}" == mirror/* ]]
}
_is_pre_builder() {
  local name="$1"
  for b in "${_PRE_BUILDERS[@]}"; do
    [[ "${name}" == "${b}" ]] && return 0
  done
  return 1
}

# FG-025 + FG-046 + FG-048 + FG-071: builder/python-trixie + builder/go-trixie
# + builder/node-trixie + builder/zig-trixie are pre-base builder images. Every
# scratch / from-Go / from-Node / from-Zig derivative's builder stage FROMs one
# of them. They must publish BEFORE anything that depends on them. Centralizing
# the special-case here keeps build.yml table-driven.
_FORGE_BUILDERS=(builder/python-trixie builder/go-trixie builder/node-trixie builder/zig-trixie)
_is_builder() {
  local name="$1"
  for b in "${_FORGE_BUILDERS[@]}"; do
    [[ "${name}" == "${b}" ]] && return 0
  done
  return 1
}

ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/_image_yaml.sh disable=SC1091
. "${ROOT}/scripts/_image_yaml.sh"

# FG-066: compute the canonical image name from an image.yaml path.
# Flat `images/<name>/image.yaml` → `<name>`; nested (one level deeper)
# `images/<tier>/<name>/image.yaml` → `<tier>/<name>`. Only one level
# of nesting is supported today (mirror/).
_rel_name() {
  local yml="$1"
  local dir
  dir=$(dirname "${yml}")
  # Strip "${ROOT}/images/" prefix.
  printf '%s\n' "${dir#"${ROOT}/images/"}"
}

# FG-057: resolve `--filter` into a space-separated set of image dir names.
# For `all`, leave FILTER_SET empty (meaning "match everything downstream").
# Otherwise: split on commas, expand each token as a shell glob against
# images/*/ dir names, union the results. Fail fast if the union is empty
# (operator specified something that doesn't exist).
FILTER_SET=""
if [[ "${FILTER}" != "all" ]]; then
  _all_dirs=()
  # FG-066: walk 2 levels deep so nested `images/mirror/<name>/` dirs
  # surface as `mirror/<name>` (their canonical name throughout the
  # tooling + GHCR repo path).
  while IFS= read -r -d '' yml; do
    _all_dirs+=("$(_rel_name "${yml}")")
  done < <(find "${ROOT}/images" -mindepth 2 -maxdepth 3 -name image.yaml -print0 | sort -z)

  _matched=()
  IFS=',' read -r -a _tokens <<<"${FILTER}"
  for tok in "${_tokens[@]}"; do
    tok="${tok## }"; tok="${tok%% }"  # trim whitespace
    [[ -n "${tok}" ]] || continue
    for name in "${_all_dirs[@]}"; do
      # shellcheck disable=SC2053  # glob-match on RHS is intentional
      if [[ "${name}" == ${tok} ]]; then
        _matched+=("${name}")
      fi
    done
  done

  if [[ ${#_matched[@]} -eq 0 ]]; then
    echo "filter matched zero images: '${FILTER}'" >&2
    echo "available image dirs:" >&2
    printf '  %s\n' "${_all_dirs[@]}" >&2
    exit 2
  fi

  # Dedup.
  FILTER_SET=$(printf '%s\n' "${_matched[@]}" | sort -u | tr '\n' ' ')
fi

_in_filter_set() {
  local name="$1"
  [[ -z "${FILTER_SET}" ]] && return 0  # all mode — pass through
  [[ " ${FILTER_SET} " == *" ${name} "* ]]
}

entries=()
while IFS= read -r -d '' yml; do
  dir=$(dirname "${yml}")
  name=$(_rel_name "${yml}")
  repo=$(image_yaml_repo "${yml}")
  tag=$(image_yaml_get   "${yml}" tag)

  # Count deps — used for base/derivatives discrimination.
  dep_count=0
  while IFS= read -r _dep; do
    [[ -n "${_dep}" ]] && dep_count=$((dep_count + 1))
  done < <(image_yaml_depends "${yml}")

  case "${MODE}" in
    mirrors)      _is_mirror "${name}" || continue ;;
    pre-builders) { ! _is_mirror "${name}" && _is_pre_builder "${name}"; } || continue ;;
    builders)     { ! _is_mirror "${name}" && _is_builder "${name}"; } || continue ;;
    base)         { [[ "${name}" == base/* ]] || { [[ ${dep_count} -eq 0 ]] && ! _is_mirror "${name}" && ! _is_pre_builder "${name}" && ! _is_builder "${name}"; }; } || continue ;;
    # FG-077: base/* members with depends_on must still land in `base` mode
    # (publish-base tier) so they publish BEFORE their downstream consumers
    # in publish-derivatives. Pre-FG-077 the mode filter was dep-count-only,
    # which routed base/python-{scratch,slim}-trixie + the 3 new FG-077
    # base/*-slim-trixie siblings to derivatives — causing an ordering race
    # where cadvisor/ipmi-exporter/github-runner/uptime-kuma tried to pull
    # ghcr.io/bboortz/base/*:latest before publish-base finished them.
    derivatives)  { [[ "${name}" != base/* ]] && [[ ${dep_count} -gt 0 ]] && ! _is_mirror "${name}"; } || continue ;;
    all)          ;;
    *) echo "unknown mode: ${MODE} (mirrors|pre-builders|builders|base|derivatives|all)" >&2; exit 2 ;;
  esac

  # FG-057: post-tier filter.
  _in_filter_set "${name}" || continue

  # FG-069: `safe_name` is the image_dir with `/` → `_` so it can be used
  # in GHA artifact names (actions/upload-artifact rejects `/` in names).
  safe_name="${name//\//_}"
  entries+=("$(printf '{"image_dir":"%s","repo":"%s","tag":"%s","safe_name":"%s"}' "${name}" "${repo}" "${tag}" "${safe_name}")")
done < <(find "${ROOT}/images" -mindepth 2 -maxdepth 3 -name image.yaml -print0 | sort -z)

joined=$(IFS=,; echo "${entries[*]:-}")
printf '{"include":[%s]}\n' "${joined}"
