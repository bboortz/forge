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

# FG-012: scalar lookup inside the `source:` nested block. Expected shape:
#   source:
#     git: https://github.com/bboortz/beaconry
#     ref: "665370e7..."
#     dockerfile: poc/scout/Dockerfile
#     context: poc/
#
# Empty stdout when the block or key is absent.
_image_yaml_source_get() {
  local file="$1" key="$2"
  awk -v k="${key}" '
    /^source:/ { in_src = 1; next }
    in_src && /^[^ ]/ { in_src = 0 }
    in_src {
      # Match "  key: value" (any indent, then "key:" then value).
      if ($0 ~ "^[[:space:]]+" k "[[:space:]]*:") {
        sub("^[[:space:]]+" k "[[:space:]]*:[[:space:]]*", "")
        # Strip inline comments (anything from " #" onwards) BEFORE quotes.
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        sub(/^"/, ""); sub(/"$/, "")
        sub(/^'\''/, ""); sub(/'\''$/, "")
        print
        exit
      }
    }
  ' "${file}"
}

image_yaml_source_git() {
  _image_yaml_source_get "$1" git
}

image_yaml_source_ref() {
  _image_yaml_source_get "$1" ref
}

# dockerfile defaults to "Dockerfile" when source.dockerfile is absent.
image_yaml_source_dockerfile() {
  local v
  v=$(_image_yaml_source_get "$1" dockerfile)
  printf '%s\n' "${v:-Dockerfile}"
}

# context defaults to "." when source.context is absent.
image_yaml_source_context() {
  local v
  v=$(_image_yaml_source_get "$1" context)
  printf '%s\n' "${v:-.}"
}

# Return 0 (true) if the image.yaml declares an external source.
image_yaml_has_source() {
  [[ -n "$(image_yaml_source_git "$1")" ]]
}
