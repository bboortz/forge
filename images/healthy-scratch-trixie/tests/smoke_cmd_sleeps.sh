#!/usr/bin/env bash
# Smoke: default CMD is sleep infinity, container stays up for docker's
# healthcheck to invoke /hc through the shared netns.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CONTAINER="fg030-sleep-$$"
trap 'docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: default CMD runs sleep infinity"
docker run -d --rm --name "${CONTAINER}" "${IMAGE}" >/dev/null
sleep 3

st=$(docker inspect --format '{{.State.Status}}' "${CONTAINER}" 2>/dev/null || echo "missing")
if [[ "${st}" != "running" ]]; then
  echo "  ✗ container not running after 3s (status=${st})" >&2
  docker logs "${CONTAINER}" 2>&1 | tail -10 >&2 || true
  exit 1
fi

cmd=$(docker inspect --format '{{.Config.Cmd}}' "${CONTAINER}")
if ! grep -qE 'sleep infinity' <<<"${cmd}"; then
  echo "  ✗ CMD not 'sleep infinity', got: ${cmd}" >&2
  exit 1
fi
echo "  ✓ CMD = ${cmd}, container running"

docker stop -t 5 "${CONTAINER}" >/dev/null
echo "  ✓ clean SIGTERM shutdown"
