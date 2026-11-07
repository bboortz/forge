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
# Section 1 — CI PR gate is fast (FG-018's win is preserved by FG-024's matrix)
# -----------------------------------------------------------------------------
# FG-018 originally wired `target=check-smart` into a sequential `full-check`
# job so PR CI used smart-check's scope. FG-024 restructured CI so the
# acceptance suite runs as a parallel matrix (no more sequential make check),
# which achieves the PR-speed goal without a dispatch target. We keep this
# section to assert that EITHER the old dispatch exists OR the new matrix +
# lint-verify split exists. Both outcomes satisfy FG-018's "fast PR CI" CAP.
say "1. ci.yml PR gate is fast (dispatch or matrix)"
if grep -q 'target=check-smart' .github/workflows/ci.yml; then
  pass "legacy check-smart dispatch wired"
else
  # New FG-024 shape: lint-verify + acceptance-matrix + acceptance-aggregate
  grep -q '^  lint-verify:' .github/workflows/ci.yml \
    || { echo "  ✗ neither check-smart dispatch nor lint-verify present" >&2; exit 1; }
  grep -q '^  acceptance-matrix:' .github/workflows/ci.yml \
    || { echo "  ✗ FG-024 acceptance-matrix not present" >&2; exit 1; }
  pass "FG-024 matrix structure (lint-verify + acceptance-matrix)"
fi

# -----------------------------------------------------------------------------
# Section 2 — fetch-depth: 0 for smart-check's git diff (still needed locally)
# -----------------------------------------------------------------------------
# Even under FG-024, lint-verify still uses fetch-depth: 0 so smart-check can
# run locally in developers' pre-push hook. Validate the SHAPE, not the spec
# that it lives inside a job named full-check.
say "2. some job in ci.yml uses fetch-depth: 0 for smart-check"
grep -A4 'actions/checkout@v4' .github/workflows/ci.yml | grep -q 'fetch-depth: 0' || {
  echo "  ✗ no actions/checkout invocation uses fetch-depth: 0" >&2; exit 1;
}
pass "fetch-depth: 0 present on a checkout invocation"

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
