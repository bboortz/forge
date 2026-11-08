#!/usr/bin/env bash
# Smoke — postgres-scratch-trixie ships compiled C.UTF-8 + en_US.UTF-8
# locales and honors them end-to-end. Asserts both the file presence
# (docker save | tar tf) and the runtime semantics via a sidecar-init
# cluster at en_US.UTF-8:
#   - length('€') == 1  (char count, not byte count — proves lc_ctype UTF-8)
#   - UPPER('äöü') == ÄÖÜ  (Latin-1 Supplement case mapping)
#   - ORDER BY sorts Unicode-alphabetical  (en_US.UTF-8 ≠ byte-order)
#   - pg_controldata reports LC_CTYPE=en_US.UTF-8
#
# Delivers: FG-033 Scenarios "Both locales ship", "initdb --locale=
# en_US.UTF-8 works", "length('€') == 1", "UPPER('äöü') == ÄÖÜ",
# "ORDER BY gives Unicode alphabetical".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-18}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
INIT_IMAGE="${POSTGRES_INIT_IMAGE:-postgres:18}"

VOLUME="smoke-pg-locale-$$-$RANDOM"
SERVER="smoke-pg-locale-server-$$"
TMP="$(mktemp -d)"

cleanup() {
  local rc=$?
  if [[ $rc -ne 0 ]] && docker container inspect "${SERVER}" >/dev/null 2>&1; then
    echo "--- postgres server logs ---" >&2
    docker logs "${SERVER}" 2>&1 | tail -30 >&2 || true
  fi
  docker rm -f "${SERVER}"  >/dev/null 2>&1 || true
  docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
  rm -rf "${TMP}"
  exit "${rc}"
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# 1. File presence via `docker save | tar tf`
# -----------------------------------------------------------------------------
echo "→ ${IMAGE}: both locale dirs present in image"
docker save "${IMAGE}" -o "${TMP}/image.tar"
tar -xf "${TMP}/image.tar" -C "${TMP}" manifest.json
mapfile -t layers < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for L in m[0]["Layers"]:
    print(L)
' "${TMP}/manifest.json")

found_c=0; found_en=0
for layer in "${layers[@]}"; do
  tar -xf "${TMP}/image.tar" -C "${TMP}" "${layer}"
  # grep -c + || true so pipefail + set -e don't interfere with "no match → 0"
  c_count=$(tar -tf "${TMP}/${layer}" 2>/dev/null \
            | grep -cE '(^|/)usr/lib/locale/C\.utf8/LC_CTYPE$' || true)
  en_count=$(tar -tf "${TMP}/${layer}" 2>/dev/null \
             | grep -cE '(^|/)usr/lib/locale/en_US\.utf8/LC_CTYPE$' || true)
  [[ "${c_count}"  -ge 1 ]] && found_c=1
  [[ "${en_count}" -ge 1 ]] && found_en=1
done
[[ "${found_c}"  -eq 1 ]] || { echo "  ✗ /usr/lib/locale/C.utf8/LC_CTYPE missing"  >&2; exit 1; }
[[ "${found_en}" -eq 1 ]] || { echo "  ✗ /usr/lib/locale/en_US.utf8/LC_CTYPE missing" >&2; exit 1; }
echo "  ✓ /usr/lib/locale/{C.utf8,en_US.utf8}/LC_CTYPE both present"

# -----------------------------------------------------------------------------
# 2. initdb --locale=en_US.UTF-8 via sidecar
# -----------------------------------------------------------------------------
echo "→ initdb --locale=en_US.UTF-8 via shelled sidecar (${INIT_IMAGE})"
docker run --rm -v "${VOLUME}:/var/lib/postgresql/data" \
  -e POSTGRES_PASSWORD=smoketest \
  --entrypoint="" "${INIT_IMAGE}" \
  bash -c '
    chown -R postgres:postgres /var/lib/postgresql/data &&
    su postgres -c "initdb -D /var/lib/postgresql/data --locale=en_US.UTF-8 --encoding=UTF8 -U postgres --auth-host=trust --auth-local=trust" &&
    echo "host all all 0.0.0.0/0 trust" >> /var/lib/postgresql/data/pg_hba.conf
  ' >/dev/null
echo "  ✓ cluster initialized at en_US.UTF-8"

# -----------------------------------------------------------------------------
# 3. Boot scratch postgres against that volume
# -----------------------------------------------------------------------------
echo "→ boot forge-local/${IMAGE_NAME}:${IMAGE_TAG} against the cluster"
docker run -d --name "${SERVER}" \
  -v "${VOLUME}:/var/lib/postgresql/data" \
  -p "0:5432" \
  "${IMAGE}" \
  postgres -D /var/lib/postgresql/data -c listen_addresses='*' >/dev/null

PORT=$(docker port "${SERVER}" 5432/tcp | head -1 | awk -F: '{print $NF}')
[[ -n "${PORT}" ]] || { echo "  ✗ could not resolve host port" >&2; exit 1; }

deadline=$(( $(date +%s) + 20 ))
until docker run --rm --network=host "${IMAGE}" \
        pg_isready -h 127.0.0.1 -p "${PORT}" -U postgres >/dev/null 2>&1; do
  (( $(date +%s) < deadline )) || { echo "  ✗ pg_isready timed out" >&2; exit 1; }
  sleep 0.5
done
echo "  ✓ pg_isready on :${PORT}"

# -----------------------------------------------------------------------------
# 4. UTF-8 behavior probes via psql
# -----------------------------------------------------------------------------
psql_q() {
  docker run --rm --network=host "${IMAGE}" \
    psql -h 127.0.0.1 -p "${PORT}" -U postgres -At -c "$1"
}

# 4a. character-count vs byte-count
got=$(psql_q "SELECT length('€')")
[[ "${got}" == "1" ]] || { echo "  ✗ length('€') = '${got}', expected '1'" >&2; exit 1; }
got=$(psql_q "SELECT octet_length('€')")
[[ "${got}" == "3" ]] || { echo "  ✗ octet_length('€') = '${got}', expected '3'" >&2; exit 1; }
echo "  ✓ length('€') == 1  AND  octet_length('€') == 3"

# 4b. case mapping on Latin-1 Supplement
got=$(psql_q "SELECT UPPER('äöü')")
[[ "${got}" == "ÄÖÜ" ]] || { echo "  ✗ UPPER('äöü') = '${got}', expected 'ÄÖÜ'" >&2; exit 1; }
echo "  ✓ UPPER('äöü') == ÄÖÜ"

# 4c. Unicode-alphabetical sort (en_US.UTF-8), not byte order (C.UTF-8)
got=$(psql_q "SELECT val FROM (VALUES ('ä'),('z'),('a')) t(val) ORDER BY val")
expected=$'a\nä\nz'
[[ "${got}" == "${expected}" ]] || {
  echo "  ✗ ORDER BY under en_US.UTF-8 returned: ${got//$'\n'/,}, expected a,ä,z" >&2
  exit 1
}
echo "  ✓ ORDER BY ('ä','z','a') == a, ä, z  (Unicode alphabetical)"

# -----------------------------------------------------------------------------
# 5. pg_controldata reports the chosen locale
# -----------------------------------------------------------------------------
# postgres 18 moved lc_ctype / lc_collate out of GUC — they're per-
# database columns in pg_database now. SHOW lc_ctype raises "unrecognized
# configuration parameter"; the catalog query is the supported path.
ctype=$(psql_q "SELECT datctype FROM pg_database WHERE datname = current_database()")
[[ "${ctype}" == "en_US.UTF-8" ]] || {
  echo "  ✗ datctype = '${ctype}', expected 'en_US.UTF-8'" >&2
  exit 1
}
collate=$(psql_q "SELECT datcollate FROM pg_database WHERE datname = current_database()")
[[ "${collate}" == "en_US.UTF-8" ]] || {
  echo "  ✗ datcollate = '${collate}', expected 'en_US.UTF-8'" >&2
  exit 1
}
echo "  ✓ pg_database.datctype + datcollate both report en_US.UTF-8"
