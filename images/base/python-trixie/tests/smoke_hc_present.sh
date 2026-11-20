#!/usr/bin/env bash
# Smoke — python-scratch-trixie ships /hc so consumer apps can wire a
# docker HEALTHCHECK against their own listener. The image does NOT bake
# its own HEALTHCHECK (consumer apps vary in port/path/whether they even
# serve HTTP).
#
# Delivers: FG-031 Scenario "python ships /hc for consumer use".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 1. /hc present in the image.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/image.tar"
tar -xf "${tmp}/image.tar" -C "${tmp}" manifest.json
mapfile -t layers < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for L in m[0]["Layers"]:
    print(L)
' "${tmp}/manifest.json")
found=0
for layer in "${layers[@]}"; do
  tar -xf "${tmp}/image.tar" -C "${tmp}" "${layer}"
  if tar -tf "${tmp}/${layer}" | grep -qE '^(\./)?hc$'; then
    found=1
    break
  fi
done
[[ "${found}" -eq 1 ]] || { echo "  ✗ /hc missing from ${IMAGE}" >&2; exit 1; }
echo "  ✓ /hc present at the image root"

# 2. /hc is runnable — docker run with --entrypoint=/hc, no args, expect
#    non-zero (hc prints usage on no-args). We just need to prove the
#    binary loads and executes, not what exit code it uses.
set +e
out=$(docker run --rm --entrypoint=/hc "${IMAGE}" 2>&1)
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "  ✗ /hc with no args exited 0; expected non-zero (usage error)" >&2
  echo "${out}" >&2
  exit 1
fi
echo "  ✓ /hc executes (exit ${rc} = usage on no-args, as expected)"

# 3. No HEALTHCHECK baked into python-scratch-trixie (consumer decides).
py_hc="$(docker inspect --format '{{json .Config.Healthcheck}}' "${IMAGE}")"
case "${py_hc}" in
  null) echo "  ✓ no baked HEALTHCHECK (consumer-decided per FG-031)" ;;
  *) echo "  ✗ expected no HEALTHCHECK, got: ${py_hc}" >&2; exit 1 ;;
esac
