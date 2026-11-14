#!/usr/bin/env bash
# Smoke — Node.js runtime matches an active LTS (v22 or v24). FG-048
# bumped from node:22-trixie-slim → node:24-trixie-slim; the matcher
# accepts both so a future node:26 LTS bump stays valid without the
# smoke needing surgery per minor.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/local/bin/node "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ node --version exited ${rc}: ${out}" >&2
  exit 1
fi
case "${out}" in
  v22.*|v24.*|v26.*) ;;
  *) echo "  ✗ expected Node v22.*/v24.*/v26.* (active LTS lines), got: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ Node.js ${out}"
