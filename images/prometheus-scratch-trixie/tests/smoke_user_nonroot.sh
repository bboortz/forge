#!/usr/bin/env bash
# Smoke — prometheus runs as uid 65534 nobody.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

user="$(docker inspect --format '{{.Config.User}}' "${IMAGE}")"
[[ "${user}" == "65534:65534" ]] \
  || { echo "  ✗ image USER = '${user}', expected '65534:65534'" >&2; exit 1; }
echo "  ✓ image USER = 65534:65534 (upstream prom/prometheus parity)"
