#!/usr/bin/env bash
# Smoke: /etc/ssl/certs/ca-certificates.crt present (inherited from pre-builder).
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE_REF}" -c "
import os, sys
p = '/etc/ssl/certs/ca-certificates.crt'
if not os.path.isfile(p):
    print(f'  ✗ CA bundle missing at {p}', file=sys.stderr); sys.exit(1)
if os.path.getsize(p) < 1024:
    print(f'  ✗ CA bundle suspiciously small: {os.path.getsize(p)} bytes', file=sys.stderr); sys.exit(1)
" >/dev/null
echo "  ✓ CA bundle present at /etc/ssl/certs/ca-certificates.crt"
