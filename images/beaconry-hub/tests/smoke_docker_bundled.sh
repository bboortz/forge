#!/usr/bin/env bash
# Hub bundles /usr/local/bin/docker (BC-009, static binary). Verify present + executable.
#
# Delivers: FG-014 Scenario "bundled CLI: docker".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-hub}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/docker "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]] || ! grep -qi '^docker version' <<<"${out}"; then
  echo "  ✗ docker --version failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ /usr/local/bin/docker present; ${out}"
