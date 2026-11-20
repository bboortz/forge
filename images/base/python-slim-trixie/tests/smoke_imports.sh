#!/usr/bin/env bash
# Smoke: base/python-slim-trixie carries a working Python 3 stdlib.
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE_REF}" -c "import ssl, hashlib, json, urllib.request" >/dev/null
echo "  ✓ stdlib imports ok (ssl, hashlib, json, urllib.request)"
