#!/usr/bin/env bash
# Central smoke-test driver. Discovers every images/<dir>/tests/smoke_*.sh,
# resolves each script's IMAGE_NAME / IMAGE_TAG / REGISTRY from the image's
# image.yaml, and runs the script in that env.
#
# Usage:
#   scripts/test-images.sh                 # all images
#   scripts/test-images.sh python-scratch-trixie  # one image
#
# Env overrides:
#   REGISTRY (default: forge-local)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
REGISTRY="${REGISTRY:-forge-local}"
SCOPE="${1:-}"

# shellcheck source=scripts/_image_yaml.sh
. "${ROOT}/scripts/_image_yaml.sh"

if [[ -n "${SCOPE}" ]]; then
  image_dirs=("${ROOT}/images/${SCOPE}")
  [[ -d "${image_dirs[0]}" ]] || { echo "no such image dir: ${image_dirs[0]}" >&2; exit 1; }
else
  mapfile -t image_dirs < <(find "${ROOT}/images" -mindepth 1 -maxdepth 1 -type d | sort)
fi

shopt -s nullglob
total=0
fail=0

for dir in "${image_dirs[@]}"; do
  test -f "${dir}/image.yaml" || continue
  repo=$(image_yaml_get "${dir}/image.yaml" repo)
  tag=$(image_yaml_get  "${dir}/image.yaml" tag)

  tests=("${dir}/tests/"smoke_*.sh)
  [[ ${#tests[@]} -eq 0 ]] && { echo "→ ${dir##*/}: no smoke scripts, skipping"; continue; }

  echo "→ ${dir##*/} (${repo}:${tag}): ${#tests[@]} script(s)"
  for t in "${tests[@]}"; do
    total=$((total+1))
    echo "  • $(basename "${t}")"
    if ! IMAGE_NAME="${repo}" IMAGE_TAG="${tag}" REGISTRY="${REGISTRY}" bash "${t}"; then
      fail=$((fail+1))
    fi
  done
done

echo
echo "test-images: ${total} script(s), ${fail} failure(s)"
[[ ${fail} -eq 0 ]]
