#!/usr/bin/env bash
# Smoke: /hc is present + runnable; /usr/bin/sleep + /usr/bin/wget are
# NOT present (dropped from FG-030 — hc provides both check + idle).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE}: /hc usage banner mentions idle"
# hc exits 2 on usage error (no args). Capture via variable to dodge pipefail.
set +e
out=$(docker run --rm --entrypoint=/hc "${IMAGE}" 2>&1)
set -e
if ! grep -qE 'usage: hc ' <<<"${out}"; then
  echo "  ✗ expected 'usage: hc' banner, got: ${out}" >&2
  exit 1
fi
if ! grep -qE 'hc idle' <<<"${out}"; then
  echo "  ✗ 'hc idle' not in usage output — HC-006 required" >&2
  exit 1
fi
echo "  ✓ /hc runs; idle mode available"

echo "→ ${IMAGE}: /usr/bin/sleep is NOT present (FG-030 uses hc idle instead)"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"; docker rm -f "fg030-abs-$$" >/dev/null 2>&1 || true' EXIT
cid=$(docker create --name "fg030-abs-$$" --entrypoint=/nonexistent "${IMAGE}")

for absent in /usr/bin/sleep /usr/bin/wget /usr/bin/nc /lib/x86_64-linux-gnu/libc.so.6; do
  if docker cp "${cid}:${absent}" "${TMP}/absent" 2>/dev/null; then
    echo "  ✗ ${absent} still present — should have been dropped in v2" >&2
    exit 1
  fi
done
echo "  ✓ /usr/bin/sleep, /usr/bin/wget, /usr/bin/nc, libc.so.6 all absent"
