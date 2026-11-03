#!/usr/bin/env bash
# Internal helper — minimal YAML reader + repo-name derivation for the
# strict `images/<dir>/image.yaml` schema. Not a general YAML parser.
#
#   source scripts/_image_yaml.sh
#   tag=$(image_yaml_get  images/python-scratch-trixie/image.yaml tag)
#   repo=$(image_yaml_repo images/python-scratch-trixie/image.yaml)

# Return the value of a scalar top-level key from image.yaml. Returns
# non-zero when the key is missing — callers can use that as a signal.
image_yaml_get() {
  local file="$1" key="$2"
  local value
  # Strip optional single or double quotes around the value (e.g. `tag: "3.13"`
  # is quoted to prevent YAML from interpreting 3.13 as a float).
  value=$(awk -v k="${key}" '
    $1 == k":" {
      $1 = ""; sub(/^ +/, ""); sub(/ +$/, "")
      sub(/^"/, ""); sub(/"$/, "")
      sub(/^'\''/, ""); sub(/'\''$/, "")
      print; exit
    }
  ' "${file}")
  [[ -n "${value}" ]] && printf '%s\n' "${value}"
}

# Return the publishable repo name for an image.yaml. Prefers an explicit
# `repo:` entry (back-compat for image dirs that need a non-matching repo
# name); otherwise derives it from the image dir's basename (FG-004).
image_yaml_repo() {
  local file="$1"
  local explicit
  explicit=$(image_yaml_get "${file}" repo)
  if [[ -n "${explicit}" ]]; then
    printf '%s\n' "${explicit}"
    return 0
  fi
  basename "$(dirname "${file}")"
}
