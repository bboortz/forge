#!/usr/bin/env bash
# Smoke: /hc + /usr/bin/sleep are present + runnable; /usr/bin/wget is
# NOT present (FG-030 proves we dropped it from the FG-029 v1 approach).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE}: /hc usage banner"
# hc exits 2 on usage errors (expected when called with no args).
# Capture output into a variable so pipefail doesn't fire on non-zero.
set +e
out=$(docker run --rm --entrypoint=/hc "${IMAGE}" 2>&1)
set -e
if ! grep -qE 'usage: hc ' <<<"${out}"; then
  echo "  ✗ expected 'usage: hc' banner, got: ${out}" >&2
  exit 1
fi
echo "  ✓ /hc runs"

echo "→ ${IMAGE}: sleep (via CMD default or explicit exec)"
out=$(docker run --rm --entrypoint=/usr/bin/sleep "${IMAGE}" --help 2>&1 | head -1)
if ! grep -qE 'Usage:.* [Ss]leep|Usage:.*/sleep' <<<"${out}"; then
  echo "  ✗ expected sleep usage banner, got: ${out}" >&2
  exit 1
fi
echo "  ✓ /usr/bin/sleep runs"

echo "→ ${IMAGE}: /usr/bin/wget is NOT present (dropped from v1)"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"; docker rm -f "fg030-abs-$$" >/dev/null 2>&1 || true' EXIT
cid=$(docker create --name "fg030-abs-$$" --entrypoint=/nonexistent "${IMAGE}")
if docker cp "${cid}:/usr/bin/wget" "${TMP}/wget" 2>/dev/null; then
  echo "  ✗ /usr/bin/wget still present — should have been dropped" >&2
  exit 1
fi
echo "  ✓ /usr/bin/wget absent — GnuTLS stack dropped"
