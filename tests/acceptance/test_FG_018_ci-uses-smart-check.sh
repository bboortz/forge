#!/usr/bin/env bash
#
# Covers: FG-018
# CAPs:   tooling.smart-check, build.pr-ci
#
# Validates .github/workflows/ci.yml wires PR → smart-check and keeps
# push-to-dev → full check. Also exercises smart-check with
# GITHUB_BASE_REF=dev + a synthetic diff to confirm dispatch resolution
# works in the CI-environment shape.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-018]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — full-check job uses check-smart on PR, check on push-to-dev
# -----------------------------------------------------------------------------
say "1. ci.yml full-check job gates on event type"
grep -q 'target=check-smart' .github/workflows/ci.yml || {
  echo "  ✗ .github/workflows/ci.yml doesn't set target=check-smart on PR" >&2; exit 1;
}
grep -q 'target=check-strict' .github/workflows/ci.yml || {
  echo "  ✗ .github/workflows/ci.yml doesn't set target=check-strict for full-check label" >&2; exit 1;
}
grep -q 'target=check' .github/workflows/ci.yml || {
  echo "  ✗ .github/workflows/ci.yml doesn't set target=check for push-to-dev" >&2; exit 1;
}
pass "three targets wired (check-smart / check-strict / check)"

# -----------------------------------------------------------------------------
# Section 2 — fetch-depth: 0 for smart-check's git diff
# -----------------------------------------------------------------------------
say "2. actions/checkout uses fetch-depth: 0 so smart-check can diff vs origin/dev"
grep -A4 'actions/checkout@v4' .github/workflows/ci.yml | grep -q 'fetch-depth: 0' || {
  echo "  ✗ full-check's actions/checkout lacks fetch-depth: 0" >&2; exit 1;
}
pass "fetch-depth: 0 present"

# -----------------------------------------------------------------------------
# Section 3 — smart-check honors GITHUB_BASE_REF in a CI-shape invocation
# -----------------------------------------------------------------------------
say "3. smart-check dispatch with GITHUB_BASE_REF set"
# Commit any dirty state so the base-ref ladder is well-defined.
_WIP=0
if ! git diff --quiet HEAD -- . 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git add -A
  git -c user.email=fg018@test -c user.name=FG018 commit -q --no-verify -m "FG-018 test checkpoint" >/dev/null
  _WIP=1
fi
BASE_SHA=$(git rev-parse HEAD)

cleanup() {
  cd "$(git rev-parse --show-toplevel)"
  git reset --hard "${BASE_SHA}" >/dev/null 2>&1 || true
  [[ "${_WIP}" -eq 1 ]] && git reset --mixed HEAD~1 >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Create a synthetic docs-only commit on top; override BASE to simulate "PR vs dev".
mkdir -p docs
echo "fg-018 synth" > docs/fg-018-ci-test.md
git add docs/fg-018-ci-test.md
git -c user.email=fg018@test -c user.name=FG018 commit -q --no-verify -m "docs: ci-test synth" >/dev/null
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=test-fast-only' <<<"${out}" || {
  echo "  ✗ smart-check didn't dispatch test-fast-only for docs-only CI-like diff" >&2
  echo "${out}" >&2
  exit 1
}
pass "smart-check dispatches test-fast-only on docs-only PR diff"

# -----------------------------------------------------------------------------
# Section 4 — workflow lints clean (hadolint / actionlint equivalent)
# -----------------------------------------------------------------------------
say "4. updated ci.yml passes yamllint"
yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}" .github/workflows/ci.yml >/dev/null
pass "ci.yml yamllint-clean"

echo
echo "FG-018 acceptance: all sections passed."
