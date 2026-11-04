#!/usr/bin/env bash
# Internal helper — minimal YAML reader + repo derivation + depends_on
# list for the strict `images/<dir>/image.yaml` schema. Not general YAML.
#
#   source scripts/_image_yaml.sh
#   tag=$(image_yaml_get  images/python-scratch-trixie/image.yaml tag)
#   repo=$(image_yaml_repo images/python-scratch-trixie/image.yaml)
#   mapfile -t deps < <(image_yaml_depends images/python-scratch-trixie/image.yaml)

# Return the value of a scalar top-level key. Returns non-zero when absent.
image_yaml_get() {
  local file="$1" key="$2"
  local value
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

# Return the publishable repo name. Prefers an explicit `repo:` entry;
# otherwise derives it from the image dir's basename (FG-004).
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

# Emit one image_dir per line from the `depends_on:` list of image.yaml.
# Expected shape:
#   depends_on:
#     - scratch-base-trixie
#     - other-base
# No-op (returns 0 with empty stdout) when absent.
image_yaml_depends() {
  local file="$1"
  awk '
    /^depends_on:/ { in_deps = 1; next }
    in_deps && /^[^ ]/ { in_deps = 0 }
    in_deps && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      sub(/^"/, ""); sub(/"$/, "")
      print
    }
  ' "${file}"
}
