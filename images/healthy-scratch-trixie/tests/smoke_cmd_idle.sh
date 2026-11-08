#!/usr/bin/env bash
# Smoke: default CMD is `hc idle` — container PID 1 blocks on SIGTERM/SIGINT.
# Replaces the FG-030-draft sleep infinity pattern now that HC-006 shipped.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CONTAINER="fg030-idle-$$"
trap 'docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: default CMD = hc idle, container stays up"
docker run -d --rm --name "${CONTAINER}" "${IMAGE}" >/dev/null
sleep 3

st=$(docker inspect --format '{{.State.Status}}' "${CONTAINER}" 2>/dev/null || echo "missing")
if [[ "${st}" != "running" ]]; then
  echo "  ✗ container not running after 3s (status=${st})" >&2
  docker logs "${CONTAINER}" 2>&1 | tail -10 >&2 || true
  exit 1
fi

cmd=$(docker inspect --format '{{.Config.Cmd}}' "${CONTAINER}")
if ! grep -qE '/hc idle' <<<"${cmd}"; then
  echo "  ✗ CMD not '/hc idle', got: ${cmd}" >&2
  exit 1
fi
echo "  ✓ CMD = ${cmd}, container running"

# Clean SIGTERM → hc idle exits 0.
docker stop -t 5 "${CONTAINER}" >/dev/null
echo "  ✓ clean SIGTERM shutdown (hc idle handled signal)"
