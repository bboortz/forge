#!/usr/bin/env bash
# Smoke — apt-upgrade step actually ran. Signal: /var/log/apt/history.log
# exists and records an upgrade transaction, OR the image contains more
# than the bare upstream package set (ca-certificates was apt-installed).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-pre-builder/debian-slim-sid}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/dpkg "${IMAGE}" -l ca-certificates 2>&1 | grep -q '^ii' \
  || { echo "  ✗ ca-certificates not installed — apt-upgrade step didn't run?" >&2; exit 1; }
echo "  ✓ apt-upgrade + ca-certificates install applied"
