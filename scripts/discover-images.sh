#!/usr/bin/env bash
# Emit a GHA-matrix JSON listing every images/<dir>/image.yaml.
#
# Output shape (single line, suitable for GITHUB_OUTPUT):
#   {"include":[{"image_dir":"python-slim-trixie","repo":"python","tag":"3.13-slim-trixie"},
#               {"image_dir":"python-scratch-trixie","repo":"python","tag":"3.13-scratch-trixie"}]}
#
# Used by .github/workflows/build.yml so adding a new images/<dir>/ auto-
# enrolls it in the daily publish matrix with no workflow edit.
#
# Falls back to empty `include:` list if there are no image dirs (keeps GHA
# matrix evaluation happy — and makes the "no images" state explicit).

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/_image_yaml.sh
. "${ROOT}/scripts/_image_yaml.sh"

entries=()
while IFS= read -r -d '' dir; do
  test -f "${dir}/image.yaml" || continue
  name=$(basename "${dir}")
  repo=$(image_yaml_get "${dir}/image.yaml" repo)
  tag=$(image_yaml_get  "${dir}/image.yaml" tag)
  entries+=("$(printf '{"image_dir":"%s","repo":"%s","tag":"%s"}' "${name}" "${repo}" "${tag}")")
done < <(find "${ROOT}/images" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

joined=$(IFS=,; echo "${entries[*]:-}")
printf '{"include":[%s]}\n' "${joined}"
