#!/usr/bin/env bash
# Scout bundles /usr/local/bin/syft. Validate it's present + executable
# by invoking `syft --version` inside the container.
#
# Delivers: FG-012 Scenario "scout ships a working syft".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-scout}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/syft "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ syft --version exited ${rc}" >&2
  echo "  output: ${out}" >&2
  exit 1
fi
if ! grep -qi 'syft' <<<"${out}"; then
  echo "  ✗ syft --version output doesn't name syft: ${out}" >&2
  exit 1
fi

echo "  ✓ /usr/local/bin/syft present; --version → ${out}"
