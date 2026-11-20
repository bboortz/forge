#!/usr/bin/env bash
# Smoke: pip install works (dual-duty builder-stage capability).
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Use --entrypoint to run pip directly; pick a tiny pure-python package.
# Install to /tmp (world-writable per baseline) so this works for the uid 65532
# nonroot default. HOME isn't set for 65532, so --user would try /.local which
# is unwritable. --target is the explicit path — same pattern consumers use
# when staging install output for a scratch COPY.
docker run --rm --entrypoint=pip "${IMAGE_REF}" install --no-cache-dir --target=/tmp/install --no-deps wheel >/dev/null
echo "  ✓ pip install --target=/tmp/install succeeded as nonroot uid 65532"
