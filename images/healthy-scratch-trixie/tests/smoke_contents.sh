#!/usr/bin/env bash
# Smoke: /hc + /usr/bin/sleep + libc + ld-linux + /sbom.json present;
# /usr/bin/wget + GnuTLS libs absent; SBOM is valid.
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

for path in /hc /usr/bin/sleep /lib64/ld-linux-x86-64.so.2 \
            /lib/x86_64-linux-gnu/libc.so.6 /sbom.json; do
  if ! docker cp "${CID}:${path}" "${TMP}/$(basename "${path}")" >/dev/null 2>&1; then
    echo "  ✗ required file missing: ${path}" >&2
    exit 1
  fi
done
echo "  ✓ /hc + sleep + libc + ld-linux + /sbom.json present"

for path in /usr/bin/wget /usr/bin/nc /lib/x86_64-linux-gnu/libgnutls.so.30; do
  if docker cp "${CID}:${path}" "${TMP}/absent" 2>/dev/null; then
    echo "  ✗ file should be absent but is present: ${path}" >&2
    exit 1
  fi
done
echo "  ✓ wget/nc/libgnutls absent (v1 → v2 dropped the GnuTLS stack)"

if ! python3 -c "
import json
d = json.load(open('${TMP}/sbom.json'))
assert d.get('bomFormat') == 'CycloneDX', f'wrong bomFormat: {d.get(\"bomFormat\")}'
comps = d.get('components') or []
assert len(comps) > 0, 'empty components list'
" 2>&1; then
  echo "  ✗ /sbom.json malformed" >&2
  exit 1
fi
echo "  ✓ /sbom.json is well-formed CycloneDX"
