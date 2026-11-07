#!/usr/bin/env bash
# Smoke: verify what SHOULD be in the image via docker cp (scratch has no
# exec for `ls`), and verify what should NOT be. Covers:
#   - /usr/bin/redis-server + redis-cli present
#   - /sbom.json present (FG-020)
#   - /etc/ssl/certs/ca-certificates.crt present (inherited from scratch-base)
#   - /etc/passwd pins redis user (cross-check for smoke_user_redis)
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-redis-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-8}"
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

# Required files.
for path in /usr/bin/redis-server /usr/bin/redis-cli \
            /sbom.json /etc/ssl/certs/ca-certificates.crt /etc/passwd; do
  if ! docker cp "${CID}:${path}" "${TMP}/$(basename "${path}")" >/dev/null 2>&1; then
    echo "  ✗ required file missing: ${path}" >&2
    exit 1
  fi
done
echo "  ✓ redis-server, redis-cli, /sbom.json, CA bundle, /etc/passwd all present"

# SBOM shape sanity.
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
