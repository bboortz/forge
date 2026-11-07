#!/usr/bin/env bash
# Smoke: redis-server boots, accepts a redis-cli PING, serves SET/GET,
# terminates cleanly on SIGTERM.
#
# redis 8 enables protected-mode by default, which blocks connections that
# arrive via docker-proxy / published ports (they appear non-local to the
# server). To stay in protected-mode (the realistic default), we run
# redis-cli from a SIDECAR container sharing the server's network namespace
# — the loopback path redis considers trusted. The sidecar reuses our own
# image (redis-cli is right there).

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-redis-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-8}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

SERVER="fg027-redis-$$"
trap 'docker rm -f "${SERVER}" >/dev/null 2>&1 || true' EXIT

echo "→ ${IMAGE}: boot server (private docker network, protected-mode default)"
docker run -d --rm --name "${SERVER}" "${IMAGE}" >/dev/null

# Helper: run redis-cli inside a sidecar sharing SERVER's netns.
cli() {
  docker run --rm --network="container:${SERVER}" --entrypoint=/usr/bin/redis-cli "${IMAGE}" "$@"
}

# Wait up to 30s for the server to accept PINGs.
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if out=$(cli PING 2>&1) && [[ "${out}" == "PONG" ]]; then
    echo "  ✓ PING→PONG (attempt ${i})"
    break
  fi
  sleep 2
  if [[ "${i}" == "15" ]]; then
    echo "  ✗ redis-server never answered PING" >&2
    docker logs "${SERVER}" 2>&1 | tail -20 >&2
    exit 1
  fi
done

# Exercise SET/GET round-trip over the sidecar.
cli SET fg027-key fg027-val >/dev/null
got=$(cli GET fg027-key)
if [[ "${got}" != "fg027-val" ]]; then
  echo "  ✗ SET/GET round-trip: expected 'fg027-val', got '${got}'" >&2
  exit 1
fi
echo "  ✓ SET/GET round-trip"

# Clean termination.
docker stop -t 5 "${SERVER}" >/dev/null
echo "  ✓ clean SIGTERM shutdown"
