#!/usr/bin/env bash
# Smoke — postgres-scratch-trixie contains no /bin/sh or other shells.
#
# Delivers: FG-007 Scenario "no shell in postgres-scratch-trixie".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-18}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for shell in /bin/sh /bin/bash /bin/dash /usr/bin/sh; do
  if docker run --rm --entrypoint="${shell}" "${IMAGE}" -c 'true' 2>/dev/null; then
    echo "  ✗ ${shell} present in ${IMAGE} — scratch must not ship a shell" >&2
    exit 1
  fi
done
echo "  ✓ no /bin/sh, /bin/bash, /bin/dash, or /usr/bin/sh in ${IMAGE}"
