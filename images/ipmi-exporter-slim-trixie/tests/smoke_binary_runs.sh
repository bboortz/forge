#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ prometheus-ipmi-exporter --version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
case "${out}" in
  *"ipmi_exporter, version 1.10"*) ;;
  *) echo "  ✗ unexpected --version output: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ $(echo "${out}" | head -1)"
