#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-alertmanager-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.28}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

user="$(docker inspect --format '{{.Config.User}}' "${IMAGE}")"
[[ "${user}" == "65534:65534" ]] \
  || { echo "  ✗ image USER = '${user}', expected '65534:65534'" >&2; exit 1; }
echo "  ✓ image USER = 65534:65534 (upstream prom/alertmanager parity)"
