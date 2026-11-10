#!/usr/bin/env bash
# Helper: extract the Go stdlib version embedded in a binary inside a
# docker image + fail if it's below go1.27 (FG-046's forge-builder-go-trixie
# toolchain floor).
#
# Usage:  . tests/acceptance/_lib_image_go_stdlib.sh
#         assert_image_go_stdlib_27plus forge-local/<img>:<tag> /usr/bin/<binary>

# shellcheck shell=bash

image_go_stdlib() {
  local image="$1" bin="$2"
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" RETURN
  docker save "${image}" -o "${tmp}/i.tar"
  (cd "${tmp}" && tar xf i.tar) >/dev/null 2>&1
  python3 - "${tmp}" "${bin}" <<'PY'
import json, tarfile, pathlib, subprocess, sys, tempfile
root, binpath = sys.argv[1], sys.argv[2].lstrip('/')
m = json.loads(pathlib.Path(f"{root}/manifest.json").read_text())
for layer_file in m[0]['Layers']:
    lp = pathlib.Path(f"{root}/{layer_file}")
    try:
        with tarfile.open(lp) as t:
            if binpath in t.getnames():
                with tempfile.TemporaryDirectory() as td:
                    t.extract(binpath, td)
                    out = subprocess.check_output(['strings', f'{td}/{binpath}']).decode()
                    for line in out.split('\n'):
                        if line.startswith('go1.'):
                            print(line.split()[0])
                            sys.exit(0)
    except Exception:
        pass
sys.exit(1)
PY
}

assert_image_go_stdlib_27plus() {
  local image="$1" bin="$2"
  local sv
  sv="$(image_go_stdlib "${image}" "${bin}")"
  case "${sv}" in
    go1.2[7-9]*|go1.[3-9]*) echo "${sv}" ;;
    *) echo "  ✗ ${image} ${bin}: stdlib = '${sv}' (want go1.27+)" >&2; return 1 ;;
  esac
}

assert_no_stdlib_critical() {
  local image="$1"
  local crit
  crit=$(grype "${image}" -o json 2>/dev/null \
    | jq -r '.matches[] | select(.vulnerability.severity == "Critical" and .artifact.name == "stdlib") | .vulnerability.id' | sort -u)
  if [[ -n "${crit}" ]]; then
    echo "  ✗ ${image}: stdlib CRITICAL CVEs present: ${crit}" >&2
    return 1
  fi
}
