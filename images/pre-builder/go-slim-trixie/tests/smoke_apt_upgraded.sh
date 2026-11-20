#!/usr/bin/env bash
# Smoke — apt-upgrade step actually ran (ca-certificates + dumb-init installed).
set -euo pipefail
IMAGE_NAME="${IMAGE_NAME:-pre-builder/go-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for pkg in ca-certificates dumb-init; do
  docker run --rm --entrypoint=/usr/bin/dpkg "${IMAGE}" -l "${pkg}" 2>&1 | grep -q '^ii' \
    || { echo "  ✗ ${pkg} not installed — apt-upgrade step didn't run?" >&2; exit 1; }
done
echo "  ✓ apt-upgrade + ca-certificates + dumb-init install applied"
