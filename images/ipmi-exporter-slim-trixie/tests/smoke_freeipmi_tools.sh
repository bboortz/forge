#!/usr/bin/env bash
# Smoke — freeipmi-tools binaries present (shell-image check).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for bin in ipmimonitoring ipmi-sel ipmi-dcmi ipmi-chassis; do
  set +e
  docker run --rm --entrypoint="/bin/sh" "${IMAGE}" -c "test -x /usr/sbin/${bin}" 2>&1
  rc=$?
  set -e
  [[ "${rc}" -eq 0 ]] \
    || { echo "  ✗ /usr/sbin/${bin} missing or not executable (rc=${rc})" >&2; exit 1; }
done
echo "  ✓ ipmimonitoring, ipmi-sel, ipmi-dcmi, ipmi-chassis all present at /usr/sbin/"
