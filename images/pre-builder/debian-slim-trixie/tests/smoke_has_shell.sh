#!/usr/bin/env bash
# Smoke: /bin/sh is present (slim contract).
set -euo pipefail
: "${IMAGE_NAME:=debian-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/bin/sh "${IMAGE_REF}" -c 'echo ok' 2>&1)
rc=$?
set -e
if [[ "${rc}" -ne 0 || "${out}" != "ok" ]]; then
  echo "  ✗ /bin/sh -c 'echo ok' failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ /bin/sh present (slim contract)"
