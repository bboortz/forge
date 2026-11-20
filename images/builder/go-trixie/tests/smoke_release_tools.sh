#!/usr/bin/env bash
# Smoke: git + curl + jq present (upstream-release resolution tools).
set -euo pipefail
: "${IMAGE_NAME:=forge-builder-go-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for bin in git curl jq; do
  docker run --rm --entrypoint="/usr/bin/${bin}" "${IMAGE_REF}" --version >/dev/null 2>&1 \
    || { echo "  ✗ /usr/bin/${bin} missing or broken" >&2; exit 1; }
done
echo "  ✓ git + curl + jq all present"
