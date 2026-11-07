#!/usr/bin/env bash
# Smoke: verify required files are in the image. Scratch has no exec for
# `ls`, so we extract via docker cp.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mosquitto-scratch-trixie}"
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

echo "→ ${IMAGE}: inspect static contents"
CID=$(docker create --entrypoint=/nonexistent "${IMAGE}")

for path in /usr/sbin/mosquitto /usr/bin/mosquitto_sub /usr/bin/mosquitto_pub \
            /usr/bin/mosquitto_passwd \
            /mosquitto/config/mosquitto.conf \
            /sbom.json /etc/ssl/certs/ca-certificates.crt /etc/passwd; do
  if ! docker cp "${CID}:${path}" "${TMP}/$(basename "${path}")" >/dev/null 2>&1; then
    echo "  ✗ required file missing: ${path}" >&2
    exit 1
  fi
done
echo "  ✓ mosquitto server + clients + default config + /sbom.json + CA bundle + /etc/passwd all present"

if ! python3 -c "
import json
d = json.load(open('${TMP}/sbom.json'))
assert d.get('bomFormat') == 'CycloneDX', f'wrong bomFormat: {d.get(\"bomFormat\")}'
assert len(d.get('components') or []) > 0, 'empty components list'
" 2>&1; then
  echo "  ✗ /sbom.json is not well-formed CycloneDX JSON" >&2
  exit 1
fi
echo "  ✓ /sbom.json is well-formed CycloneDX"
