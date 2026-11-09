#!/usr/bin/env bash
# Smoke — container runs as uid 1000 (upstream `node` user).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

cfg_user=$(docker inspect --format '{{.Config.User}}' "${IMAGE}")
case "${cfg_user}" in
  node|1000|1000:*) ;;
  *) echo "  ✗ expected Config.User == 'node' / '1000', got '${cfg_user}'" >&2; exit 1 ;;
esac
echo "  ✓ Config.User = '${cfg_user}' (nonroot)"
