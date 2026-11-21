#!/usr/bin/env bash
# Smoke: /app/REVISION contains the upstream SHA this build was clipped from.
set -euo pipefail

: "${IMAGE_NAME:=psitransfer-slim-trixie}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

sha=$(docker run --rm "${IMAGE}" -e "
const fs = require('fs');
process.stdout.write(fs.readFileSync('/app/REVISION', 'utf8').trim());")
# Upstream commit SHAs are 40 hex chars.
[[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || { echo "  ✗ /app/REVISION not a 40-char SHA: ${sha}" >&2; exit 1; }
echo "  ✓ /app/REVISION = ${sha}"
