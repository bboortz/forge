#!/usr/bin/env bash
# Smoke — /syft runs + reports a version (matches upstream anchore/syft).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mirror/syft}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ syft version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
# Upstream syft version output includes a line like:
#   Version:       1.57.0  (or similar)
if ! echo "${out}" | grep -qE 'Version:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+'; then
  echo "  ✗ syft version output doesn't contain a version line:" >&2
  echo "${out}" >&2
  exit 1
fi
ver=$(echo "${out}" | awk -F: '/Version:/ { gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit }')
echo "  ✓ syft runs; Version: ${ver}"
