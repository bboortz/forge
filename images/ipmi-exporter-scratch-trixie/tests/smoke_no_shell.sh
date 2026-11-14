#!/usr/bin/env bash
# Smoke — no shell in the scratch runtime. Different from the slim
# variant's `smoke_has_shell.sh` which positively asserts a shell.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for shell in /bin/sh /bin/bash /bin/dash /usr/bin/sh; do
  if docker run --rm --entrypoint="${shell}" "${IMAGE}" -c 'true' 2>/dev/null; then
    echo "  ✗ ${shell} present in ${IMAGE}" >&2
    exit 1
  fi
done
echo "  ✓ no /bin/sh, /bin/bash, /bin/dash, or /usr/bin/sh"
