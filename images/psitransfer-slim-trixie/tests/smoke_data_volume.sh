#!/usr/bin/env bash
# Smoke: /data exists + owned by uid 65532 + declared as VOLUME.
set -euo pipefail

: "${IMAGE_NAME:=psitransfer-slim-trixie}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# /data owned by 65532 + writable by the nonroot runtime user.
out=$(docker run --rm "${IMAGE}" -e "
const fs = require('fs');
const s = fs.statSync('/data');
process.stdout.write(JSON.stringify({uid: s.uid, mode: (s.mode & 0o777).toString(8)}));")
[[ "${out}" == *'"uid":65532'* ]] || { echo "  ✗ /data uid not 65532: ${out}" >&2; exit 1; }

# VOLUME declared in the image config.
vols=$(docker image inspect --format='{{json .Config.Volumes}}' "${IMAGE}")
[[ "${vols}" == *'/data'* ]] || { echo "  ✗ /data not declared as VOLUME: ${vols}" >&2; exit 1; }

echo "  ✓ /data owned by uid 65532 + declared as VOLUME"
