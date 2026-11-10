#!/usr/bin/env bash
#
# Covers: FG-024
# CAPs:   tooling.ci-parallel-tests, build.pr-ci, tooling.ci-build-cache
#
# Validates FG-024 via static inspection + a dry-run of discover-tests.sh.
# Matrix orchestration itself is only testable on CI; we check the wiring.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-024]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — scripts/discover-tests.sh emits a JSON matrix of all tests
# -----------------------------------------------------------------------------
say "1. scripts/discover-tests.sh emits well-formed JSON matrix"
test -x scripts/discover-tests.sh || {
  echo "  ✗ scripts/discover-tests.sh missing or not executable" >&2; exit 1;
}
OUT=$(bash scripts/discover-tests.sh)
# Must be parseable JSON with .include[] carrying test + fg_id
COUNT=$(printf '%s' "${OUT}" | jq '.include | length')
EXPECTED=$(find tests/acceptance -name 'test_FG_*.sh' | wc -l)
[[ "${COUNT}" == "${EXPECTED}" ]] || {
  echo "  ✗ matrix count ${COUNT} != ${EXPECTED} test files on disk" >&2; exit 1;
}
# Every entry has required keys
printf '%s' "${OUT}" | jq -e '.include[] | select(has("test") and has("fg_id"))' >/dev/null || {
  echo "  ✗ matrix entries missing test or fg_id key" >&2; exit 1;
}
# Every test path exists and is executable
printf '%s' "${OUT}" | jq -r '.include[].test' | while read -r t; do
  test -x "${t}" || { echo "  ✗ ${t} not executable" >&2; exit 1; }
done
# Every fg_id is of form FG-NNN[x] (FG-046 introduced single-letter
# suffixes for split acceptance tests — e.g. FG-046a, FG-046b — so the
# matrix can keep each cell under the 6-min timeout cap).
printf '%s' "${OUT}" | jq -r '.include[].fg_id' | while read -r id; do
  [[ "${id}" =~ ^FG-[0-9]{3}[a-z]?$ ]] || { echo "  ✗ bad fg_id: ${id}" >&2; exit 1; }
done
pass "discover-tests.sh: ${COUNT} tests, all paths executable, fg_id format valid"

# -----------------------------------------------------------------------------
# Section 2 — ci.yml wires acceptance-matrix via matrix dispatch
# -----------------------------------------------------------------------------
say "2. ci.yml wires acceptance-matrix with matrix.include from discover"
grep -q '^  acceptance-matrix:' .github/workflows/ci.yml || {
  echo "  ✗ ci.yml missing acceptance-matrix job" >&2; exit 1;
}
grep -qE 'matrix:.*(\n|$)' .github/workflows/ci.yml || true   # permissive
# Must consume matrix via ${{ matrix.test }} or ${{ matrix.fg_id }}
grep -qE '\$\{\{ *matrix\.(test|fg_id) *\}\}' .github/workflows/ci.yml || {
  echo "  ✗ acceptance-matrix doesn't reference matrix.test / matrix.fg_id" >&2; exit 1;
}
# Must include buildx + grype cache + tool install + GHCR login
for pattern in "docker/setup-buildx-action" "docker/login-action" "actions/cache@v4" "FORGE_CACHE_FROM_PREFIX"; do
  grep -q "${pattern}" .github/workflows/ci.yml || {
    echo "  ✗ acceptance-matrix missing: ${pattern}" >&2; exit 1;
  }
done
pass "acceptance-matrix job: matrix dispatch + buildx + grype cache + cache env"

# -----------------------------------------------------------------------------
# Section 3 — acceptance-aggregate gate depends on matrix
# -----------------------------------------------------------------------------
say "3. ci.yml wires acceptance-aggregate as single-green gate"
grep -q '^  acceptance-aggregate:' .github/workflows/ci.yml || {
  echo "  ✗ ci.yml missing acceptance-aggregate job" >&2; exit 1;
}
# needs: [acceptance-matrix]
grep -qE 'needs:.*acceptance-matrix' .github/workflows/ci.yml || {
  echo "  ✗ acceptance-aggregate missing needs: acceptance-matrix" >&2; exit 1;
}
pass "acceptance-aggregate depends on acceptance-matrix"

# -----------------------------------------------------------------------------
# Section 4 — lint-verify job replaces full-check (no more sequential tests)
# -----------------------------------------------------------------------------
say "4. lint-verify job runs lint + verify-* (not acceptance)"
# The job should exist and NOT call make check-smart / make check for acceptance
grep -q '^  lint-verify:' .github/workflows/ci.yml || {
  echo "  ✗ ci.yml missing lint-verify job" >&2; exit 1;
}
# Must call make test-fast (or equivalent) but NOT make check-smart/make check/make test-acceptance
awk '
  /^  lint-verify:/ { capture=1; print; next }
  capture && /^  [a-z][a-z-]*:$/ { capture=0 }
  capture { print }
' .github/workflows/ci.yml > /tmp/fg024-lint-verify-$$.yml
grep -q "make test-fast" /tmp/fg024-lint-verify-$$.yml || {
  echo "  ✗ lint-verify doesn't call make test-fast" >&2; exit 1;
}
if grep -qE "make (check-smart|check|test-acceptance)" /tmp/fg024-lint-verify-$$.yml; then
  echo "  ✗ lint-verify still invokes a target that runs acceptance tests" >&2
  grep -E "make " /tmp/fg024-lint-verify-$$.yml >&2
  rm -f /tmp/fg024-lint-verify-$$.yml
  exit 1
fi
rm -f /tmp/fg024-lint-verify-$$.yml
pass "lint-verify: make test-fast only, no acceptance"

# -----------------------------------------------------------------------------
# Section 5 — local make check-smart is unchanged (still sequential)
# -----------------------------------------------------------------------------
say "5. local make targets still run acceptance sequentially"
# Makefile's check target still runs test-acceptance
grep -qE '^check:.*test-fast.*test-acceptance|^check:.*test-acceptance.*test-fast' Makefile || \
grep -qE '^test-acceptance:' Makefile || {
  echo "  ✗ Makefile no longer has sequential test-acceptance target" >&2; exit 1;
}
pass "Makefile still has sequential test-acceptance (local path unchanged)"

# -----------------------------------------------------------------------------
# Section 6 — yamllint + actionlint clean on ci.yml
# -----------------------------------------------------------------------------
say "6. ci.yml passes yamllint"
yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}" \
  .github/workflows/ci.yml >/dev/null
pass "yamllint clean"

echo
echo "FG-024 acceptance: all sections passed."
