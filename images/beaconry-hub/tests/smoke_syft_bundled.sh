#!/usr/bin/env bash
# Hub bundles /usr/local/bin/syft for post-fix re-verification.
#
# Delivers: FG-014 Scenario "bundled CLI: syft".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-hub}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/syft "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]] || ! grep -qi 'syft' <<<"${out}"; then
  echo "  ✗ syft --version failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ /usr/local/bin/syft present; ${out}"
