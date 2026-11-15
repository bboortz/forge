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
_PRE_BUILDERS=(debian-slim-trixie debian-slim-sid python-slim-trixie ubuntu-slim-noble)
_is_pre_builder() {
  local name="$1"
  for b in "${_PRE_BUILDERS[@]}"; do
    [[ "${name}" == "${b}" ]] && return 0
  done
  return 1
}

# FG-025 + FG-046 + FG-048: forge-builder-python-trixie + forge-builder-go-trixie
# + forge-builder-node-trixie are pre-base builder images. Every scratch /
# from-Go / from-Node derivative's builder stage FROMs one of them. They
# must publish BEFORE anything that depends on them. Centralizing the
# special-case here keeps build.yml table-driven.
_FORGE_BUILDERS=(forge-builder-python-trixie forge-builder-go-trixie forge-builder-node-trixie)
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

# FG-057: resolve `--filter` into a space-separated set of image dir names.
# For `all`, leave FILTER_SET empty (meaning "match everything downstream").
# Otherwise: split on commas, expand each token as a shell glob against
# images/*/ dir names, union the results. Fail fast if the union is empty
# (operator specified something that doesn't exist).
FILTER_SET=""
if [[ "${FILTER}" != "all" ]]; then
  _all_dirs=()
  while IFS= read -r -d '' dir; do
    _all_dirs+=("$(basename "${dir}")")
  done < <(find "${ROOT}/images" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

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
while IFS= read -r -d '' dir; do
  test -f "${dir}/image.yaml" || continue
  name=$(basename "${dir}")
  repo=$(image_yaml_repo "${dir}/image.yaml")
  tag=$(image_yaml_get   "${dir}/image.yaml" tag)

  # Count deps — determines tier.
  dep_count=0
  while IFS= read -r _dep; do
    [[ -n "${_dep}" ]] && dep_count=$((dep_count + 1))
  done < <(image_yaml_depends "${dir}/image.yaml")

  case "${MODE}" in
    pre-builders) _is_pre_builder "${name}" || continue ;;
    builders)     _is_builder "${name}" || continue ;;
    base)         { [[ ${dep_count} -eq 0 ]] && ! _is_pre_builder "${name}" && ! _is_builder "${name}"; } || continue ;;
    derivatives)  [[ ${dep_count} -gt 0 ]] || continue ;;
    all)          ;;
    *) echo "unknown mode: ${MODE} (pre-builders|builders|base|derivatives|all)" >&2; exit 2 ;;
  esac

  # FG-057: post-tier filter.
  _in_filter_set "${name}" || continue

  entries+=("$(printf '{"image_dir":"%s","repo":"%s","tag":"%s"}' "${name}" "${repo}" "${tag}")")
done < <(find "${ROOT}/images" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

joined=$(IFS=,; echo "${entries[*]:-}")
printf '{"include":[%s]}\n' "${joined}"
