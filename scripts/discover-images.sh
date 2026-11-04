#!/usr/bin/env bash
# Emit a GHA-matrix JSON listing image dirs. Modes:
#
#   scripts/discover-images.sh            → every image (legacy caller)
#   scripts/discover-images.sh base       → images with no depends_on
#   scripts/discover-images.sh derivatives → images WITH depends_on
#
# build.yml uses the two-mode split so baselines publish before
# derivatives that FROM them (FG-005).
#
# Output shape (single line, suitable for GITHUB_OUTPUT):
#   {"include":[{"image_dir":"...","repo":"...","tag":"..."}, ...]}

set -euo pipefail

MODE="${1:-all}"

ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/_image_yaml.sh
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
    base)        [[ ${dep_count} -eq 0 ]] || continue ;;
    derivatives) [[ ${dep_count} -gt 0 ]] || continue ;;
    all)         ;;
    *) echo "unknown mode: ${MODE} (base|derivatives|all)" >&2; exit 2 ;;
  esac

  entries+=("$(printf '{"image_dir":"%s","repo":"%s","tag":"%s"}' "${name}" "${repo}" "${tag}")")
done < <(find "${ROOT}/images" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

joined=$(IFS=,; echo "${entries[*]:-}")
printf '{"include":[%s]}\n' "${joined}"
