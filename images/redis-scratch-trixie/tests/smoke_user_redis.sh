#!/usr/bin/env bash
# Smoke: /etc/passwd pins redis user to uid 999 (Docker Hub convention).
# Scratch has no `id` binary — we inspect the file via docker export.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-redis-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-8}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE}: redis uid pinned to 999 in /etc/passwd"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"; docker rm -f "fg027-u-$$" >/dev/null 2>&1 || true' EXIT
cid=$(docker create --name "fg027-u-$$" --entrypoint=/nonexistent "${IMAGE}")
docker cp "${cid}:/etc/passwd" "${TMP}/passwd" >/dev/null

if ! grep -q '^redis:x:999:999:' "${TMP}/passwd"; then
  echo "  ✗ /etc/passwd doesn't pin redis uid=999 gid=999:" >&2
  grep '^redis' "${TMP}/passwd" >&2 || echo "  (no redis entry at all)" >&2
  exit 1
fi
echo "  ✓ redis:x:999:999: present"
