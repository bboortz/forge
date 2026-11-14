#!/usr/bin/env bash
# Smoke — /etc/os-release reports Ubuntu 24.04 noble.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ubuntu-slim-noble}"
IMAGE_TAG="${IMAGE_TAG:-24.04}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/bin/cat "${IMAGE}" /etc/os-release 2>&1)

echo "${out}" | grep -q '^NAME="Ubuntu"' \
  || { echo "  ✗ /etc/os-release does not report NAME=Ubuntu" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q '^UBUNTU_CODENAME=noble' \
  || { echo "  ✗ /etc/os-release does not report UBUNTU_CODENAME=noble" >&2; echo "${out}" >&2; exit 1; }
echo "${out}" | grep -q '^VERSION_ID="24.04"' \
  || { echo "  ✗ /etc/os-release does not report VERSION_ID=24.04" >&2; echo "${out}" >&2; exit 1; }

echo "  ✓ Ubuntu 24.04 noble"
