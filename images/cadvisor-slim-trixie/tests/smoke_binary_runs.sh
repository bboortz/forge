#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cadvisor-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.60.6}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" -version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ cadvisor -version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
case "${out}" in
  *"cAdvisor version v0.60.6"*) ;;
  *) echo "  ✗ unexpected -version output: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ $(echo "${out}" | head -1)"
