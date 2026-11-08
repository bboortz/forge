#!/usr/bin/env bash
# Smoke: wget + nc + sleep + CA bundle + /sbom.json all present; SBOM valid.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TMP=$(mktemp -d)
CID=""
cleanup() {
  [[ -n "${CID}" ]] && docker rm "${CID}" >/dev/null 2>&1 || true
  rm -rf "${TMP}"
}
trap cleanup EXIT

echo "→ ${IMAGE}: inspect static contents"
CID=$(docker create --entrypoint=/nonexistent "${IMAGE}")

for path in /usr/bin/wget /usr/bin/nc /usr/bin/sleep \
            /sbom.json /etc/ssl/certs/ca-certificates.crt /etc/passwd; do
  if ! docker cp "${CID}:${path}" "${TMP}/$(basename "${path}")" >/dev/null 2>&1; then
    echo "  ✗ required file missing: ${path}" >&2
    exit 1
  fi
done
echo "  ✓ wget + nc + sleep + /sbom.json + CA bundle + /etc/passwd all present"

if ! python3 -c "
import json
d = json.load(open('${TMP}/sbom.json'))
assert d.get('bomFormat') == 'CycloneDX', f'wrong bomFormat: {d.get(\"bomFormat\")}'
comps = d.get('components') or []
assert len(comps) > 0, 'empty components list'
# wget + netcat-openbsd + coreutils should be in there.
names = {c.get('name') for c in comps}
for want in ('wget', 'netcat-openbsd', 'coreutils'):
    assert want in names, f'missing component {want!r} in SBOM'
" 2>&1; then
  echo "  ✗ /sbom.json malformed or missing expected components" >&2
  exit 1
fi
echo "  ✓ /sbom.json is well-formed CycloneDX; wget/netcat-openbsd/coreutils present"
