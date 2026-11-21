#!/usr/bin/env bash
#
# Covers: FG-049
# CAPs:   image.postgres-client-tools, image.postgres-client-pg_dumpall-works,
#         image.postgres-client-no-server, image.postgres-client-nonroot,
#         image.has-shell, scan.regression-gate, test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-049]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/postgres-client-slim-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         tests/smoke_client_binaries_run.sh tests/smoke_pg_dumpall_e2e.sh \
         tests/smoke_no_server_binaries.sh tests/smoke_has_shell.sh \
         tests/smoke_user_postgres.sh tests/smoke_size.sh; do
  test -e "images/postgres-client-slim-trixie/${f}" \
    || fail "images/postgres-client-slim-trixie/${f} missing"
done
# Slim images do NOT ship EXPECTATIONS.yaml (no scratch-base dependency).
test ! -e images/postgres-client-slim-trixie/EXPECTATIONS.yaml \
  || fail "images/postgres-client-slim-trixie/EXPECTATIONS.yaml should not exist (slim, not scratch)"
pass "all required files present (slim contract)"

say "2. postgres-client-slim-trixie:18 builds from debian-slim-trixie + PGDG client-18"
bash scripts/build-image.sh postgres-client-slim-trixie >/dev/null
docker image inspect forge-local/postgres-client-slim-trixie:18 >/dev/null
pass "forge-local/postgres-client-slim-trixie:18 built"

say "3. per-image smoke suite"
for s in images/postgres-client-slim-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=18 bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=18, NO depends_on (slim variant)"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/postgres-client-slim-trixie/image.yaml)
[[ "${tag}" == "18" ]] || fail "image.yaml tag = '${tag}' (want 18)"
if grep -qE '^depends_on:' images/postgres-client-slim-trixie/image.yaml; then
  fail "image.yaml should NOT have depends_on (slim variant, not scratch derivative)"
fi
pass "image.yaml correct (tag=18, no depends_on)"

say "5. postgres-scratch-trixie absence.shell cross-references postgres-client-slim-trixie"
# The doc-only fix shipped alongside this story must point operators from
# postgres-scratch's absence.shell promise to this image. Prevents the
# original 2026-11-10 operator confusion from recurring.
if ! grep -q 'postgres-client-slim-trixie' \
       images/postgres-scratch-trixie/PROMISES.yaml; then
  fail "postgres-scratch-trixie/PROMISES.yaml must reference postgres-client-slim-trixie in absence.shell description"
fi
pass "sibling cross-reference present in postgres-scratch-trixie PROMISES"

echo
echo "FG-049 acceptance: all sections passed."
