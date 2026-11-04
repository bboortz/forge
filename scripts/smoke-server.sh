#!/usr/bin/env bash
# Reusable start-wait-probe-stop helper for server images (nginx, postgres,
# future redis, …). Avoids every image's smoke suite re-implementing the
# same docker-run/polling/cleanup dance.
#
# Usage:
#   scripts/smoke-server.sh \
#     --image forge-local/nginx-scratch-trixie:1.26 \
#     --port 80 \
#     --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/' \
#     --test  'curl -sf http://localhost:__HOST_PORT__/' \
#     [--run-flags '-e FOO=bar']
#     [--timeout 15]
#
# How it works:
#   1. `docker run -d -p 0:<port>` — publishes on a random host port
#   2. Resolves the host port from `docker port <name> <port>/tcp`
#   3. Substitutes `__HOST_PORT__` in --ready and --test strings
#   4. Polls --ready every 0.5s up to --timeout; aborts if never ready
#   5. Runs --test (exit code is the smoke result)
#   6. Always captures `docker logs` on failure and `docker rm -f` on exit
#
# Exit codes: 0 = test passed, non-zero = startup failed or test failed.

set -euo pipefail

IMAGE=""
PORT=""
READY=""
TEST=""
RUN_FLAGS=""
TIMEOUT=15
CONTAINER_NAME=""

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# //; s/^#$//' >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)     IMAGE="$2";     shift 2 ;;
    --port)      PORT="$2";      shift 2 ;;
    --ready)     READY="$2";     shift 2 ;;
    --test)      TEST="$2";      shift 2 ;;
    --run-flags) RUN_FLAGS="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2";   shift 2 ;;
    -h|--help)   usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "${IMAGE}" ]] || { echo "--image required" >&2; exit 2; }
[[ -n "${PORT}"  ]] || { echo "--port required"  >&2; exit 2; }
[[ -n "${READY}" ]] || { echo "--ready required" >&2; exit 2; }
[[ -n "${TEST}"  ]] || { echo "--test required"  >&2; exit 2; }

CONTAINER_NAME="smoke-$(echo "${IMAGE}" | tr '/:' '--')-$$"

# shellcheck disable=SC2317,SC2329
# SC2317/SC2329 silenced: this function IS invoked — via `trap cleanup EXIT`
# a few lines below. Shellcheck can't see through the trap registration.
cleanup() {
  local rc=$?
  if [[ $rc -ne 0 ]] && docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "--- container logs on failure ---" >&2
    docker logs "${CONTAINER_NAME}" 2>&1 | tail -30 >&2 || true
    echo "--- end container logs ---" >&2
  fi
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  exit "${rc}"
}
trap cleanup EXIT

# shellcheck disable=SC2086  # RUN_FLAGS intentionally word-split
docker run -d --name "${CONTAINER_NAME}" -p "0:${PORT}" ${RUN_FLAGS} "${IMAGE}" >/dev/null

HOST_PORT=$(docker port "${CONTAINER_NAME}" "${PORT}/tcp" | head -1 | awk -F: '{print $NF}')
if [[ -z "${HOST_PORT}" ]]; then
  echo "could not resolve host port for ${PORT}/tcp" >&2
  exit 1
fi

READY_CMD="${READY//__HOST_PORT__/${HOST_PORT}}"
TEST_CMD="${TEST//__HOST_PORT__/${HOST_PORT}}"

deadline=$(( $(date +%s) + TIMEOUT ))
while (( $(date +%s) < deadline )); do
  if bash -c "${READY_CMD}" >/dev/null 2>&1; then
    bash -c "${TEST_CMD}"
    exit $?
  fi
  sleep 0.5
done

echo "server not ready within ${TIMEOUT}s (${READY_CMD})" >&2
exit 1
