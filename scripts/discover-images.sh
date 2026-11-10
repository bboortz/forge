#!/usr/bin/env bash
# Emit a GHA-matrix JSON listing image dirs. Modes:
#
#   scripts/discover-images.sh              → every image (legacy caller)
#   scripts/discover-images.sh pre-builders → forge-rooted slim bases (FG-042)
#   scripts/discover-images.sh builders     → shared builder-stage images (FG-025, FG-046)
#   scripts/discover-images.sh base         → images with no depends_on + not pre-builder/builder
#   scripts/discover-images.sh derivatives  → images WITH depends_on
#
# build.yml uses the four-mode split so pre-builders publish before
# builders publish before scratch-base publishes before derivatives that
# FROM any upstream forge image (FG-005, FG-025, FG-042, FG-046).
#
# Output shape (single line, suitable for GITHUB_OUTPUT):
#   {"include":[{"image_dir":"...","repo":"...","tag":"..."}, ...]}

set -euo pipefail

MODE="${1:-all}"

# FG-042: pre-builders — forge-rooted slim bases consumed by multiple
# downstream slim images. Must publish BEFORE forge-builder-trixie
# (which FROMs python-slim-trixie post-FG-042) and BEFORE cadvisor-slim
# / ipmi-exporter-slim (which FROM debian-slim-trixie).
_PRE_BUILDERS=(debian-slim-trixie python-slim-trixie)
_is_pre_builder() {
  local name="$1"
  for b in "${_PRE_BUILDERS[@]}"; do
    [[ "${name}" == "${b}" ]] && return 0
  done
  return 1
}

# FG-025 + FG-046: forge-builder-trixie + forge-builder-go-trixie are
# pre-base builder images. Every scratch/from-Go derivative's builder
# stage FROMs one of them. They must publish BEFORE anything that
# depends on them. Centralizing the special-case here keeps build.yml
# table-driven.
_FORGE_BUILDERS=(forge-builder-trixie forge-builder-go-trixie)
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

  entries+=("$(printf '{"image_dir":"%s","repo":"%s","tag":"%s"}' "${name}" "${repo}" "${tag}")")
done < <(find "${ROOT}/images" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

joined=$(IFS=,; echo "${entries[*]:-}")
printf '{"include":[%s]}\n' "${joined}"
