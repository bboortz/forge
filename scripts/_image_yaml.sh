#!/usr/bin/env bash
# Internal helper — minimal YAML reader for the two scalar keys we rely on
# (repo, tag). Does not implement general YAML; intended for the strict
# `images/<dir>/image.yaml` schema only. Exits non-zero if the key is missing.
#
#   source scripts/_image_yaml.sh
#   repo=$(image_yaml_get images/python-scratch-trixie/image.yaml repo)

image_yaml_get() {
  local file="$1" key="$2"
  local value
  value=$(awk -v k="${key}" '
    $1 == k":" { $1=""; sub(/^ +/, ""); sub(/ +$/, ""); print; exit }
  ' "${file}")
  if [[ -z "${value}" ]]; then
    echo "image_yaml_get: ${file}: key '${key}' not found or empty" >&2
    return 1
  fi
  printf '%s\n' "${value}"
}
