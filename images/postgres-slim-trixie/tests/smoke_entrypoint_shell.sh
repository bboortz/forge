#!/usr/bin/env bash
# Smoke: the upstream docker-entrypoint.sh is present, executable, and the
# /docker-entrypoint-initdb.d directory exists for SQL bootstraps.
#
# Covers FG-026's "upstream entrypoint preserved" promise — distinguishes
# this image from postgres-scratch-trixie which has neither shell nor
# docker-entrypoint.sh.
set -euo pipefail

: "${IMAGE_NAME:=postgres-slim-trixie}"
: "${IMAGE_TAG:=18}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE_REF}: docker-entrypoint.sh executable"
docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -x /usr/local/bin/docker-entrypoint.sh
echo "  ✓ docker-entrypoint.sh is executable"

echo "→ ${IMAGE_REF}: /docker-entrypoint-initdb.d/ exists"
docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -d /docker-entrypoint-initdb.d
echo "  ✓ initdb.d dir exists"

echo "→ ${IMAGE_REF}: /bin/bash present (upstream entrypoint is bash)"
docker run --rm --entrypoint=/bin/bash "${IMAGE_REF}" -c 'echo bash works'
echo "  ✓ bash runs"
