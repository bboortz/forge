#!/usr/bin/env bash
#
# Covers: FG-026
# CAPs:   image.postgres-slim-nextcloud-compatible, image.postgres-serves-sql
#
# Validates (1) new postgres-slim-trixie image carries postgres 18 + the
# full upstream entrypoint, and (2) postgres-scratch-trixie was bumped
# from 17 to 18 cleanly.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-026]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — postgres-slim-trixie image dir + required files
# -----------------------------------------------------------------------------
say "1. images/postgres-slim-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         tests/smoke_postgres_version.sh tests/smoke_entrypoint_shell.sh \
         tests/smoke_psql.sh tests/smoke_ca_bundle.sh tests/smoke_size.sh; do
  test -e "images/postgres-slim-trixie/${f}" \
    || { echo "  ✗ images/postgres-slim-trixie/${f} missing" >&2; exit 1; }
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — postgres-slim-trixie builds + preserves upstream entrypoint
# -----------------------------------------------------------------------------
say "2. postgres-slim-trixie builds + upstream entrypoint intact"
if ! docker image inspect forge-local/postgres-slim-trixie:18 >/dev/null 2>&1; then
  bash scripts/build-image.sh postgres-slim-trixie >/dev/null
fi
IMAGE_TAG=18 bash images/postgres-slim-trixie/tests/smoke_postgres_version.sh
IMAGE_TAG=18 bash images/postgres-slim-trixie/tests/smoke_entrypoint_shell.sh
IMAGE_TAG=18 bash images/postgres-slim-trixie/tests/smoke_psql.sh
IMAGE_TAG=18 bash images/postgres-slim-trixie/tests/smoke_ca_bundle.sh
pass "postgres-slim-trixie core smokes pass"

# -----------------------------------------------------------------------------
# Section 3 — postgres-slim-trixie honors custom config mount
# -----------------------------------------------------------------------------
say "3. postgres-slim-trixie honors a mounted postgresql.conf override"
TMPDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '${TMPDIR}'; docker rm -f fg026-cfg-$$ >/dev/null 2>&1 || true" EXIT
# Minimal config: distinctive port to prove our conf is the one in effect.
cat > "${TMPDIR}/postgresql.conf" <<'EOF'
listen_addresses = 'localhost'
port = 5433
shared_buffers = 128MB
EOF
cat > "${TMPDIR}/pg_hba.conf" <<'EOF'
local all postgres trust
host  all all 127.0.0.1/32 trust
EOF
# Start, wait for ready, then assert the custom port is what postgres bound to.
docker run -d --rm --name "fg026-cfg-$$" \
  -e POSTGRES_PASSWORD=unused \
  -v "${TMPDIR}/postgresql.conf:/etc/postgresql/postgresql.conf:ro" \
  -v "${TMPDIR}/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro" \
  forge-local/postgres-slim-trixie:18 \
  postgres -c config_file=/etc/postgresql/postgresql.conf \
           -c hba_file=/etc/postgresql/pg_hba.conf >/dev/null
# Wait up to 30s for the socket to be live.
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if docker exec "fg026-cfg-$$" pg_isready -h 127.0.0.1 -p 5433 >/dev/null 2>&1; then
    pass "postgres bound to custom port 5433 — custom config honored (attempt ${i})"
    docker rm -f "fg026-cfg-$$" >/dev/null 2>&1 || true
    break
  fi
  sleep 2
  if [[ "${i}" == "15" ]]; then
    echo "  ✗ postgres never became ready on custom port 5433" >&2
    docker logs "fg026-cfg-$$" 2>&1 | tail -20 >&2
    docker rm -f "fg026-cfg-$$" >/dev/null 2>&1 || true
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# Section 4 — postgres-scratch-trixie bumped to 18
# -----------------------------------------------------------------------------
say "4. postgres-scratch-trixie bumped to postgres 18"
yaml_tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' images/postgres-scratch-trixie/image.yaml)
[[ "${yaml_tag}" == "18" ]] || {
  echo "  ✗ image.yaml tag is '${yaml_tag}', expected '18'" >&2; exit 1;
}
# Dockerfile should no longer reference postgresql-17 / /usr/lib/postgresql/17.
if grep -E "(postgresql-17|/usr/lib/postgresql/17|/usr/share/postgresql/17)" images/postgres-scratch-trixie/Dockerfile; then
  echo "  ✗ postgres-scratch-trixie/Dockerfile still references postgresql-17" >&2
  exit 1
fi
pass "image.yaml tag = 18; Dockerfile has no postgresql-17 refs"

# -----------------------------------------------------------------------------
# Section 5 — PROMISES.yaml version bumped (FG-010 semver gate)
# -----------------------------------------------------------------------------
say "5. postgres-scratch-trixie PROMISES.yaml version bumped"
promises_ver=$(awk '/^version:/ {gsub(/"/, "", $2); print $2}' images/postgres-scratch-trixie/PROMISES.yaml)
# Accept any version >= 0.2 — FG-026 bumped 0.1 → 0.2, later stories
# (FG-033, …) bump further. Use sort -V for semver-aware comparison.
lowest=$(printf '0.2\n%s\n' "${promises_ver}" | sort -V | head -1)
[[ "${lowest}" == "0.2" ]] || {
  echo "  ✗ PROMISES.yaml version is '${promises_ver}', expected >= '0.2' (bumped for 17→18)" >&2
  exit 1
}
pass "PROMISES version = ${promises_ver} (≥ 0.2)"

echo
echo "FG-026 acceptance: all sections passed."
