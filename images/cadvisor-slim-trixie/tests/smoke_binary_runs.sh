#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cadvisor-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
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
# FG-050: cadvisor-slim-trixie now tracks upstream latest release
# (build.ref-latest-release CAP). Loose match: project name + "version v"
# instead of a hard-coded major.minor.patch.
case "${out}" in
  *"cAdvisor version v"*) ;;
  *) echo "  ✗ unexpected -version output: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ $(echo "${out}" | head -1)"
