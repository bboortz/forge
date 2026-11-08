#!/usr/bin/env bash
# Smoke: wget, nc, sleep binaries all present + runnable.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE}: wget --version"
out=$(docker run --rm --entrypoint=/usr/bin/wget "${IMAGE}" --version 2>&1 | head -1)
echo "  ${out}"
if ! grep -qE 'GNU Wget 1\.' <<<"${out}"; then
  echo "  ✗ expected 'GNU Wget 1.x' banner" >&2
  exit 1
fi
echo "  ✓ wget runs"

echo "→ ${IMAGE}: nc -h"
out=$(docker run --rm --entrypoint=/usr/bin/nc "${IMAGE}" -h 2>&1 | head -1)
echo "  ${out}"
if ! grep -qE 'OpenBSD netcat' <<<"${out}"; then
  echo "  ✗ expected 'OpenBSD netcat' banner" >&2
  exit 1
fi
echo "  ✓ nc (openbsd) runs"

echo "→ ${IMAGE}: sleep (direct exec, --help)"
# GNU sleep from coreutils: --help works.
out=$(docker run --rm --entrypoint=/usr/bin/sleep "${IMAGE}" --help 2>&1 | head -1)
if ! grep -qE 'Usage:.* [Ss]leep|Usage:.*/sleep' <<<"${out}"; then
  echo "  ✗ expected sleep usage banner, got: ${out}" >&2
  exit 1
fi
echo "  ✓ sleep runs"
