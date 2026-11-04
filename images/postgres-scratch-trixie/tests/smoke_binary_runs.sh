#!/usr/bin/env bash
# Smoke — postgres binary reports its version.
#
# Delivers: FG-007 Scenario "postgres binary reports version".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-17}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" postgres --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ docker run ${IMAGE} postgres --version exited ${rc}" >&2
  echo "${out}" >&2
  exit 1
fi
if ! grep -q 'PostgreSQL) 17' <<<"${out}"; then
  echo "  ✗ expected 'PostgreSQL) 17' in postgres --version output, got: ${out}" >&2
  exit 1
fi
echo "  ✓ ${out}"
