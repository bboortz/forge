#!/usr/bin/env bash
# Smoke: runtime config user is 65532.
set -euo pipefail

: "${IMAGE_NAME:=nginx-scratch-alpine}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

user=$(docker image inspect --format '{{.Config.User}}' "${IMAGE}")
[[ "${user}" == "65532" ]] || { echo "  ✗ Config.User = '${user}', want 65532" >&2; exit 1; }
echo "  ✓ Config.User = 65532"
