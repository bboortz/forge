#!/usr/bin/env bash
# Smoke — positive assertion that /bin/sh is present (slim contract).
# Counterpart to smoke_no_shell.sh in scratch images.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c 'echo ok' 2>&1)
rc=$?
set -e
if [[ "${rc}" -ne 0 || "${out}" != "ok" ]]; then
  echo "  ✗ /bin/sh -c 'echo ok' failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ /bin/sh present (slim contract — operator debugging via docker exec)"
