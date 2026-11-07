#!/usr/bin/env bash
# Smoke: /etc/passwd pins mosquitto user to uid 1883 (Eclipse convention).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mosquitto-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"; docker rm -f "fg028-u-$$" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: mosquitto uid pinned to 1883 in /etc/passwd"
cid=$(docker create --name "fg028-u-$$" --entrypoint=/nonexistent "${IMAGE}")
docker cp "${cid}:/etc/passwd" "${TMP}/passwd" >/dev/null

if ! grep -q '^mosquitto:x:1883:1883:' "${TMP}/passwd"; then
  echo "  ✗ /etc/passwd doesn't pin mosquitto uid=1883 gid=1883:" >&2
  grep '^mosquitto' "${TMP}/passwd" >&2 || echo "  (no mosquitto entry at all)" >&2
  exit 1
fi
echo "  ✓ mosquitto:x:1883:1883: present"
