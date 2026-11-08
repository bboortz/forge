#!/usr/bin/env bash
#
# Covers: FG-033
# CAPs:   image.locale-utf8, image.postgres-serves-sql, image.python-scratch-nonroot
#
# Validates FG-033: both postgres-scratch-trixie:18 and
# python-scratch-trixie:3.14 ship compiled C.UTF-8 + en_US.UTF-8 locales
# so `ENV LANG=C.UTF-8` is actually honored. Postgres' initdb at
# en_US.UTF-8 produces a UTF-8-correct cluster; python's
# locale.setlocale(...) accepts both and strcoll distinguishes them.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-033]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — static invariants
# -----------------------------------------------------------------------------
say "1. source files encode the FG-033 contract"

for d in postgres-scratch-trixie python-scratch-trixie; do
  grep -qE 'localedef .*-i C +-f UTF-8 C\.UTF-8' "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing localedef C.UTF-8 compile step"
  grep -qE 'localedef .*-i en_US +-f UTF-8 en_US\.UTF-8' "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing localedef en_US.UTF-8 compile step"
  grep -qE '/usr/lib/locale/C\.utf8' "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing /usr/lib/locale/C.utf8 overlay COPY"
  grep -qE '/usr/lib/locale/en_US\.utf8' "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing /usr/lib/locale/en_US.utf8 overlay COPY"
  grep -q 'runtime.locale-utf8' "images/${d}/PROMISES.yaml" \
    || fail "images/${d}/PROMISES.yaml: missing promise runtime.locale-utf8"
  test -x "images/${d}/tests/smoke_locale_utf8.sh" \
    || fail "images/${d}/tests/smoke_locale_utf8.sh: missing or not executable"
done

grep -q 'image.locale-utf8' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md: missing CAP image.locale-utf8"

pass "all static invariants in place"

# -----------------------------------------------------------------------------
# Section 2 — build both images
# -----------------------------------------------------------------------------
say "2. build postgres-scratch-trixie + python-scratch-trixie"
bash scripts/build-image.sh postgres-scratch-trixie >/dev/null
bash scripts/build-image.sh python-scratch-trixie   >/dev/null
docker image inspect forge-local/postgres-scratch-trixie:18 >/dev/null
docker image inspect forge-local/python-scratch-trixie:3.14 >/dev/null
pass "both images built"

# -----------------------------------------------------------------------------
# Section 3 — new locale smokes + existing per-image smoke suites
# -----------------------------------------------------------------------------
say "3. locale smokes + existing image suites (regression)"

IMAGE_TAG=18 bash images/postgres-scratch-trixie/tests/smoke_locale_utf8.sh
pass "postgres smoke_locale_utf8.sh"

IMAGE_NAME=python-scratch-trixie IMAGE_TAG=3.14 \
  bash images/python-scratch-trixie/tests/smoke_locale_utf8.sh
pass "python smoke_locale_utf8.sh"

for s in images/postgres-scratch-trixie/tests/smoke_*.sh; do
  [[ "${s}" == *smoke_locale_utf8.sh ]] && continue
  IMAGE_TAG=18 bash "${s}" >/dev/null
done
pass "existing postgres smokes green"

for s in images/python-scratch-trixie/tests/smoke_*.sh; do
  [[ "${s}" == *smoke_locale_utf8.sh ]] && continue
  IMAGE_NAME=python-scratch-trixie IMAGE_TAG=3.14 bash "${s}" >/dev/null
done
pass "existing python smokes green"

# -----------------------------------------------------------------------------
# Section 4 — FG-003/007/009/026/031 regression guards
# -----------------------------------------------------------------------------
say "4. FG-003 / FG-007 / FG-009 / FG-026 / FG-031 acceptance regression"
bash tests/acceptance/test_FG_003_python-scratch-runtime.sh >/dev/null
pass "FG-003 (python-scratch-runtime)"
bash tests/acceptance/test_FG_007_postgres-scratch-trixie.sh >/dev/null
pass "FG-007 (postgres-scratch-runtime)"
bash tests/acceptance/test_FG_009_python-scratch-hardening.sh >/dev/null
pass "FG-009 (python-scratch-hardening)"
bash tests/acceptance/test_FG_026_postgres-18.sh >/dev/null
pass "FG-026 (postgres-18)"
bash tests/acceptance/test_FG_031_hc-in-service-images.sh >/dev/null
pass "FG-031 (hc-in-service-images)"

echo
echo "FG-033 acceptance: all sections passed."
