#!/usr/bin/env bash
# Scratch — asserts no /bin/sh or /bin/bash in the runtime image. Scratch
# deliberately excludes shells; attempting to run one must fail.
#
# Delivers: FG-003 Scenario "Scratch image has no shell".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.14-scratch-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Each attempted shell invocation must fail (non-zero exit from docker run
# because the executable doesn't exist in the image).
for shell in /bin/sh /bin/bash /bin/dash /usr/bin/sh; do
  if docker run --rm --entrypoint="${shell}" "${IMAGE}" -c 'true' 2>/dev/null; then
    echo "  ✗ ${shell} is present in ${IMAGE} — scratch must not ship a shell" >&2
    exit 1
  fi
done

echo "  ✓ no /bin/sh, /bin/bash, /bin/dash, or /usr/bin/sh in ${IMAGE}"
