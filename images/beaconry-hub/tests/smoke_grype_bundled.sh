#!/usr/bin/env bash
# Hub bundles /usr/local/bin/grype for CVE matching in the waterfall.
#
# Delivers: FG-014 Scenario "bundled CLI: grype".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-hub}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/grype "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]] || ! grep -qi 'grype' <<<"${out}"; then
  echo "  ✗ grype --version failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ /usr/local/bin/grype present; $(head -1 <<<"${out}")"
