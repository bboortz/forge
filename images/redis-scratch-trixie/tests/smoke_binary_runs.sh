#!/usr/bin/env bash
# Smoke: redis-server binary runs; redis-cli binary runs.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-redis-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-8}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE}: redis-server --version"
out=$(docker run --rm "${IMAGE}" --version 2>&1)
echo "  ${out}"
if ! grep -q 'Redis server v=8' <<<"${out}"; then
  echo "  ✗ expected 'Redis server v=8' in output, got: ${out}" >&2
  exit 1
fi
echo "  ✓ redis-server v8 runs"

echo "→ ${IMAGE}: redis-cli --version (via explicit entrypoint override)"
out=$(docker run --rm --entrypoint=/usr/bin/redis-cli "${IMAGE}" --version 2>&1)
echo "  ${out}"
if ! grep -qE 'redis-cli 8' <<<"${out}"; then
  echo "  ✗ expected 'redis-cli 8' in output, got: ${out}" >&2
  exit 1
fi
echo "  ✓ redis-cli v8 runs"
