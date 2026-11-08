#!/usr/bin/env bash
# Smoke: healthy-scratch-trixie contains no /bin/sh or other shells.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for shell in /bin/sh /bin/bash /bin/dash /usr/bin/sh; do
  if docker run --rm --entrypoint="${shell}" "${IMAGE}" -c "echo nope" 2>/dev/null; then
    echo "  ✗ ${shell} is present — should be absent in scratch image" >&2
    exit 1
  fi
done
echo "  ✓ no /bin/sh, /bin/bash, /bin/dash, or /usr/bin/sh in ${IMAGE}"
