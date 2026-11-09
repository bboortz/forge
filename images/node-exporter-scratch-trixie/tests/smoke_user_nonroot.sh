#!/usr/bin/env bash
# Smoke — node-exporter runs as uid 65532 nonroot.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-node-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.9}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

user="$(docker inspect --format '{{.Config.User}}' "${IMAGE}")"
[[ "${user}" == "65532:65532" ]] \
  || { echo "  ✗ image USER = '${user}', expected '65532:65532'" >&2; exit 1; }
echo "  ✓ image USER = 65532:65532 (distroless nonroot)"
