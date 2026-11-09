#!/usr/bin/env bash
# Smoke — ENV SSL_CERT_FILE re-declared + CA bundle present.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-alertmanager-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.28}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

env_vars="$(docker inspect --format '{{json .Config.Env}}' "${IMAGE}")"
case "${env_vars}" in
  *'SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt'*) ;;
  *) echo "  ✗ SSL_CERT_FILE env not set: ${env_vars}" >&2; exit 1 ;;
esac
case "${env_vars}" in
  *'SSL_CERT_DIR=/etc/ssl/certs'*) ;;
  *) echo "  ✗ SSL_CERT_DIR env not set: ${env_vars}" >&2; exit 1 ;;
esac
echo "  ✓ ENV SSL_CERT_FILE + SSL_CERT_DIR re-declared"

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
found_ca=0
for L in "${layers[@]}"; do
  tar -xf "${TMP}/i.tar" -C "${TMP}" "${L}"
  c=$(tar -tf "${TMP}/${L}" 2>/dev/null \
      | grep -cE '(^|/)etc/ssl/certs/ca-certificates\.crt$' || true)
  [[ "${c}" -ge 1 ]] && found_ca=1
done
[[ "${found_ca}" -eq 1 ]] \
  || { echo "  ✗ /etc/ssl/certs/ca-certificates.crt missing" >&2; exit 1; }
echo "  ✓ /etc/ssl/certs/ca-certificates.crt present"
