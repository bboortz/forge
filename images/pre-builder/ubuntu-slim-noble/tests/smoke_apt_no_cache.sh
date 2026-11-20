#!/usr/bin/env bash
# Smoke — /var/lib/apt/lists/ carries no Packages/Release files.
# Downstream Dockerfiles that `apt-get install` MUST re-run `apt-get update`.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-pre-builder/ubuntu-slim-noble}"
IMAGE_TAG="${IMAGE_TAG:-24.04}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/usr/bin/find "${IMAGE}" /var/lib/apt/lists -type f 2>/dev/null || true)
if [[ -n "${out}" ]]; then
  echo "  ✗ /var/lib/apt/lists/ contains files — cleanup missed" >&2
  echo "${out}" >&2
  exit 1
fi
echo "  ✓ /var/lib/apt/lists/ is empty (apt-get update cache cleared)"
