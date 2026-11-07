#!/usr/bin/env bash
# Smoke: mosquitto-server boots on the baked default config, accepts
# PUBLISH + SUBSCRIBE from a sidecar container sharing its netns, and
# terminates cleanly on SIGTERM.

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mosquitto-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

SERVER="fg028-mosquitto-$$"
trap 'docker rm -f "${SERVER}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: boot broker (default-permissive config)"
docker run -d --rm --name "${SERVER}" "${IMAGE}" >/dev/null

# Wait up to 15s for the broker to accept connections via sidecar PUB.
for i in 1 2 3 4 5 6 7 8; do
  if docker run --rm --network="container:${SERVER}" \
       --entrypoint=/usr/bin/mosquitto_pub "${IMAGE}" \
       -h localhost -t 'fg028/boot' -m ok >/dev/null 2>&1; then
    echo "  ✓ broker accepting clients (attempt ${i})"
    break
  fi
  sleep 1
  if [[ "${i}" == "8" ]]; then
    echo "  ✗ broker never accepted a mosquitto_pub" >&2
    docker logs "${SERVER}" 2>&1 | tail -15 >&2
    exit 1
  fi
done

# PUB → SUB round-trip. Start sub FIRST, then pub, so the subscribe
# session is established when the publish lands. Use retained=false; sub
# uses -C 1 to exit after one message.
TMP=$(mktemp -d)
trap 'docker rm -f "${SERVER}" >/dev/null 2>&1 || true; rm -rf "${TMP}"' EXIT

docker run --rm --network="container:${SERVER}" \
  --entrypoint=/usr/bin/mosquitto_sub "${IMAGE}" \
  -h localhost -t 'fg028/pubsub' -C 1 -W 5 > "${TMP}/sub.out" 2>&1 &
SUB_PID=$!
sleep 1

docker run --rm --network="container:${SERVER}" \
  --entrypoint=/usr/bin/mosquitto_pub "${IMAGE}" \
  -h localhost -t 'fg028/pubsub' -m 'hello-fg028' >/dev/null

wait "${SUB_PID}" || true
got=$(cat "${TMP}/sub.out")
if [[ "${got}" != "hello-fg028" ]]; then
  echo "  ✗ PUB→SUB round-trip: expected 'hello-fg028', got: '${got}'" >&2
  exit 1
fi
echo "  ✓ PUB→SUB round-trip"

# Clean termination.
docker stop -t 5 "${SERVER}" >/dev/null
echo "  ✓ clean SIGTERM shutdown"
