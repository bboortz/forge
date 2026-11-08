#!/usr/bin/env bash
# Smoke: /hc + /sbom.json present; sleep + wget + nc + libc all absent.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TMP=$(mktemp -d)
CID=""
cleanup() {
  [[ -n "${CID}" ]] && docker rm "${CID}" >/dev/null 2>&1 || true
  rm -rf "${TMP}"
}
trap cleanup EXIT

CID=$(docker create --entrypoint=/nonexistent "${IMAGE}")

for path in /hc /sbom.json; do
  if ! docker cp "${CID}:${path}" "${TMP}/$(basename "${path}")" >/dev/null 2>&1; then
    echo "  ✗ required file missing: ${path}" >&2
    exit 1
  fi
done
echo "  ✓ /hc + /sbom.json present"

for absent in /usr/bin/sleep /usr/bin/wget /usr/bin/nc \
              /lib/x86_64-linux-gnu/libc.so.6 \
              /lib64/ld-linux-x86-64.so.2 \
              /lib/x86_64-linux-gnu/libgnutls.so.30; do
  if docker cp "${CID}:${absent}" "${TMP}/absent" 2>/dev/null; then
    echo "  ✗ ${absent} should be absent" >&2
    exit 1
  fi
done
echo "  ✓ sleep/wget/nc/libc/ld-linux/libgnutls all absent"

if ! python3 -c "
import json
d = json.load(open('${TMP}/sbom.json'))
assert d.get('bomFormat') == 'CycloneDX', f'wrong bomFormat: {d.get(\"bomFormat\")}'
" 2>&1; then
  echo "  ✗ /sbom.json malformed" >&2
  exit 1
fi
echo "  ✓ /sbom.json is well-formed CycloneDX"
