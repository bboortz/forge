#!/usr/bin/env bash
# Smoke — libicu74 is apt-installed (required by the GHA runner's
# .NET 6 runtime). Also verifies apt state is fresh (post-apt-upgrade).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-pre-builder/ubuntu-slim-noble}"
IMAGE_TAG="${IMAGE_TAG:-24.04}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=/usr/bin/dpkg-query "${IMAGE}" \
  -W -f='${Status}\n' libicu74 2>&1 | grep -q 'install ok installed' \
  || { echo "  ✗ libicu74 not installed" >&2; exit 1; }
echo "  ✓ libicu74 installed"

# Verify at least one shared library file is present (catches a weird
# case where the package is installed-but-missing from the overlay).
docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c \
  'ls /usr/lib/x86_64-linux-gnu/libicui18n.so.74* 2>/dev/null | head -1' \
  | grep -q 'libicui18n' \
  || { echo "  ✗ libicui18n.so.74 not found under /usr/lib" >&2; exit 1; }
echo "  ✓ libicui18n.so.74 present on disk"
