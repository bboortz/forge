#!/usr/bin/env bash
# Smoke — documents the root-user exception. This specific scratch image
# runs as root (not uid 65532) because /dev/ipmi0 requires it.
# `docker inspect` User field is "" (default root).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

user="$(docker inspect --format '{{.Config.User}}' "${IMAGE}")"
if [[ -n "${user}" && "${user}" != "0" && "${user}" != "0:0" && "${user}" != "root" ]]; then
  echo "  ✗ expected root (empty / 0 / 0:0 / root), got: '${user}'" >&2
  echo "    /dev/ipmi0 requires root; non-root would break turnkey deployment." >&2
  exit 1
fi
echo "  ✓ runs as root (documented exception — /dev/ipmi0 compat)"
