#!/usr/bin/env bash
# Smoke — all 5 freeipmi ELF binaries shipped in the scratch overlay.
# Pattern: docker save | tar tf (no shell to use `docker exec test -x`).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
docker save "${IMAGE}" -o "${TMP}/i.tar"
tar -xf "${TMP}/i.tar" -C "${TMP}" manifest.json
mapfile -t layers < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for L in m[0]["Layers"]:
    print(L)
' "${TMP}/manifest.json")

declare -A found
for bin in bmc-info ipmi-sensors ipmi-chassis ipmi-dcmi ipmi-sel; do
  found[$bin]=0
done

for L in "${layers[@]}"; do
  tar -xf "${TMP}/i.tar" -C "${TMP}" "${L}"
  for bin in "${!found[@]}"; do
    c=$(tar -tf "${TMP}/${L}" 2>/dev/null \
        | grep -cE "(^|/)usr/sbin/${bin}\$" || true)
    [[ "${c}" -ge 1 ]] && found[$bin]=1
  done
done

missing=()
for bin in "${!found[@]}"; do
  [[ "${found[$bin]}" -eq 0 ]] && missing+=("/usr/sbin/${bin}")
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "  ✗ missing freeipmi ELF binaries:" >&2
  printf '    %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "  ✓ all 5 freeipmi ELF binaries (bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi, ipmi-sel) shipped"
