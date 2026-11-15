#!/usr/bin/env bash
# Smoke — /bin/ping is present + runnable. Uptime Kuma's "Ping" monitor
# type shells out to it; without this, operators see
# `ping: command not found` in the container logs on first Ping monitor.
# Added by FG-055.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# `ping -V` prints version and exits 0 without needing ICMP capability
# (so the smoke works in CI containers without NET_RAW).
set +e
out=$(docker run --rm --entrypoint=/bin/ping "${IMAGE}" -V 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ /bin/ping -V exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
echo "  ✓ /bin/ping present: $(echo "${out}" | head -1)"
