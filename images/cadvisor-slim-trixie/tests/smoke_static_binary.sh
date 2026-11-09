#!/usr/bin/env bash
# Smoke — /usr/bin/cadvisor is a statically-linked Go binary.
#
# CGO_ENABLED=0 at build time means the binary has zero dynamic deps.
# Confirming this guards against a silent config drift where someone
# flips CGO on (which would re-introduce a libc dep) without updating
# the EXPECTATIONS/PROMISES contract.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cadvisor-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.60.6}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/usr/bin/ldd "${IMAGE}" /usr/bin/cadvisor 2>&1)
set -e
# ldd on a static binary exits non-zero on glibc with "not a dynamic executable",
# so we ignore its rc and pattern-match on stdout instead.
case "${out}" in
  *"not a dynamic executable"*|*"statically linked"*) ;;
  *) echo "  ✗ expected static binary; ldd said: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ /usr/bin/cadvisor is a static Go binary (no dyn deps)"
