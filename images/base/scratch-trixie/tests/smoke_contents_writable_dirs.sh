#!/usr/bin/env bash
# Baseline writable-dirs contract (FG-008): /tmp (1777), /var/tmp (1777),
# /nonroot (owned 65532:65532, mode 0755). Any derivative or consumer that
# writes ephemeral state can rely on /tmp + /var/tmp; apps running as
# nonroot (65532) get a HOME at /nonroot.
#
# Delivers: FG-008 Scenario "baseline provides writable /tmp, /var/tmp, /nonroot".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

# Walk every layer's tar for the entries we care about. tar tvf format:
#   drwxrwxrwt root/root 0 2024-01-01 12:00 tmp/
# → mode  / uid-gid (name or number) / size / date / time / path
check_entry() {
  local path="$1" want_mode="$2" want_owner="$3" found=0
  for layer in "${tmp}"/blobs/sha256/*; do
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      found=1
      local mode owner
      mode=$(awk '{print $1}' <<<"${line}")
      owner=$(awk '{print $2}' <<<"${line}")
      if [[ "${mode}" != "${want_mode}" ]]; then
        echo "  ✗ ${path}: mode ${mode}, want ${want_mode}" >&2
        return 1
      fi
      # tar may report owner as `name/name` (when the host has a matching
      # passwd entry) or `uid/gid` (numeric, when it doesn't). Accept both
      # by normalizing root → 0.
      local owner_norm="${owner//root/0}"
      local want_norm="${want_owner//root/0}"
      if [[ "${owner_norm}" != "${want_norm}" ]]; then
        echo "  ✗ ${path}: owner ${owner}, want ${want_owner}" >&2
        return 1
      fi
      echo "  • ${path}: mode ${mode} owner ${owner}"
      break
    done < <(tar tvf "${layer}" 2>/dev/null | grep -E "[[:space:]]${path}\$" || true)
    [[ ${found} -eq 1 ]] && break
  done
  if [[ ${found} -eq 0 ]]; then
    echo "  ✗ ${path} not found in image" >&2
    return 1
  fi
}

# tar tvf mode strings: 1777 → drwxrwxrwt; 0755 (dir) → drwxr-xr-x.
# Owner is reported "<name>/<name>" when the name maps; numeric when it
# doesn't (uid 65532 has no entry in /etc/passwd of the host, so numeric).
check_entry "tmp/"      "drwxrwxrwt" "root/root"
check_entry "var/tmp/"  "drwxrwxrwt" "root/root"
check_entry "nonroot/"  "drwxr-xr-x" "65532/65532"

echo "  ✓ /tmp (1777), /var/tmp (1777), /nonroot (0755, 65532:65532) present"
