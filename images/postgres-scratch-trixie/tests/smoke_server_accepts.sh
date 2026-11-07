#!/usr/bin/env bash
# Smoke — scratch postgres serves SELECT 1 end-to-end.
#
# Scratch has no /bin/sh, so initdb — which uses system() to probe the
# postgres binary — cannot run in-container. We use the official
# postgres:18 image as a one-shot init sidecar to populate a named volume
# with a Debian-compatible data directory, then start our scratch postgres
# from that volume. This validates that our scratch binary is wire- and
# on-disk-compatible with a stock postgres 18 cluster.
#
# Pipeline:
#   1. docker run --rm -v vol:/data postgres:18 initdb → initialize cluster
#   2. docker run -d -v vol:/var/lib/postgresql/data -p 0:5432 <scratch>
#      postgres -D /var/lib/postgresql/data → start our server
#   3. poll pg_isready from a scratch sidecar until the socket is up
#   4. psql SELECT 1 from a scratch sidecar; expect "1"
#
# Delivers: FG-007 Scenario "postgres starts and SELECT 1 works end-to-end".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-18}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
INIT_IMAGE="${POSTGRES_INIT_IMAGE:-postgres:18}"

VOLUME="smoke-pg-$$-$RANDOM"
SERVER="smoke-pg-server-$$"

cleanup() {
  local rc=$?
  if [[ $rc -ne 0 ]] && docker container inspect "${SERVER}" >/dev/null 2>&1; then
    echo "--- postgres server logs ---" >&2
    docker logs "${SERVER}" 2>&1 | tail -30 >&2 || true
  fi
  docker rm -f "${SERVER}"  >/dev/null 2>&1 || true
  docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
  exit "${rc}"
}
trap cleanup EXIT

# 1. init cluster with the official postgres:18 (shelled image can run initdb).
docker run --rm -v "${VOLUME}:/var/lib/postgresql/data" \
  -e POSTGRES_PASSWORD=smoketest -e POSTGRES_INITDB_ARGS='--locale=C --encoding=UTF8' \
  --entrypoint="" "${INIT_IMAGE}" \
  bash -c '
    chown -R postgres:postgres /var/lib/postgresql/data &&
    su postgres -c "initdb -D /var/lib/postgresql/data --locale=C --encoding=UTF8 -U postgres --auth-host=trust --auth-local=trust" &&
    echo "host all all 0.0.0.0/0 trust" >> /var/lib/postgresql/data/pg_hba.conf
  ' >/dev/null

# 2. start scratch postgres against that volume
docker run -d --name "${SERVER}" \
  -v "${VOLUME}:/var/lib/postgresql/data" \
  -p "0:5432" \
  "${IMAGE}" \
  postgres -D /var/lib/postgresql/data -c listen_addresses='*' >/dev/null

PORT=$(docker port "${SERVER}" 5432/tcp | head -1 | awk -F: '{print $NF}')
[[ -n "${PORT}" ]] || { echo "  ✗ could not resolve host port" >&2; exit 1; }

# 3. poll pg_isready from a scratch sidecar (--network=host hits localhost:PORT)
deadline=$(( $(date +%s) + 20 ))
until docker run --rm --network=host "${IMAGE}" \
        pg_isready -h 127.0.0.1 -p "${PORT}" -U postgres >/dev/null 2>&1; do
  (( $(date +%s) < deadline )) || { echo "  ✗ pg_isready timed out" >&2; exit 1; }
  sleep 0.5
done

# 4. SELECT 1 via psql from a scratch sidecar
set +e
out=$(docker run --rm --network=host "${IMAGE}" \
        psql -h 127.0.0.1 -p "${PORT}" -U postgres -At -c 'SELECT 1' 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ psql SELECT 1 exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
if [[ "${out}" != "1" ]]; then
  echo "  ✗ SELECT 1 returned '${out}', expected '1'" >&2
  exit 1
fi
echo "  ✓ ${INIT_IMAGE} initdb → scratch postgres server → scratch psql SELECT 1"
