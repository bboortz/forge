#!/usr/bin/env bash
# FG-012 — Lint every images/<name>/ for mutual-exclusion rules between
# local Dockerfile + source: block + required source fields.
#
# Exit codes:
#   0 — ok
#   1 — at least one violation
#
# Wired into make test-fast (Makefile) + pre-commit (.pre-commit-config.yaml).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

# shellcheck source=scripts/_image_yaml.sh disable=SC1091
. "${ROOT}/scripts/_image_yaml.sh"

errors=0
# FG-066: walk flat images/<name>/ + 1-nested images/<tier>/<name>/
# (currently only mirror/). A dir without image.yaml but with nested
# image.yaml children is treated as a tier container and skipped silently.
_image_dirs=()
for d in "${ROOT}"/images/*/; do
  if [[ -f "${d}image.yaml" ]]; then
    _image_dirs+=("${d}")
  else
    _has_nested=0
    for sub in "${d}"*/; do
      if [[ -f "${sub}image.yaml" ]]; then
        _image_dirs+=("${sub}")
        _has_nested=1
      fi
    done
    if [[ ${_has_nested} -eq 0 ]]; then
      _image_dirs+=("${d}")  # dangling — will fail the image.yaml-missing check
    fi
  fi
done

for d in "${_image_dirs[@]}"; do
  name=${d#"${ROOT}"/images/}
  name=${name%/}
  iy="${d}image.yaml"
  [[ -f "${iy}" ]] || { echo "  ✗ images/${name}/image.yaml missing" >&2; errors=$((errors + 1)); continue; }

  has_dockerfile=0
  [[ -e "${d}Dockerfile" ]] && has_dockerfile=1
  has_source=0
  if image_yaml_has_source "${iy}"; then
    has_source=1
  fi

  if [[ ${has_source} -eq 1 && ${has_dockerfile} -eq 1 ]]; then
    echo "  ✗ images/${name}: has both source: in image.yaml AND a local Dockerfile — mutually exclusive (FG-012)" >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ ${has_source} -eq 0 && ${has_dockerfile} -eq 0 ]]; then
    echo "  ✗ images/${name}: has neither source: nor a local Dockerfile — dangling image dir" >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ ${has_source} -eq 1 ]]; then
    git=$(image_yaml_source_git "${iy}")
    ref=$(image_yaml_source_ref "${iy}")
    if [[ -z "${git}" ]]; then
      echo "  ✗ images/${name}: source.git is empty" >&2
      errors=$((errors + 1))
    fi
    if [[ -z "${ref}" ]]; then
      echo "  ✗ images/${name}: source.ref is empty (use SHA, tag, 'latest', or branch name)" >&2
      errors=$((errors + 1))
    fi
  fi
done

if [[ ${errors} -gt 0 ]]; then
  echo "verify-image-dirs: FAIL (${errors} violation(s))" >&2
  exit 1
fi
echo "verify-image-dirs: ok"
