#!/usr/bin/env bash
# Smoke — nginx binary reports its version.
#
# Delivers: FG-006 Scenario "nginx binary reports version".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE}" -v 2>&1)
if ! grep -q 'nginx/1\.26' <<<"${out}"; then
  echo "  ✗ expected 'nginx/1.26' in -v output, got: ${out}" >&2
  exit 1
fi
echo "  ✓ ${out}"
