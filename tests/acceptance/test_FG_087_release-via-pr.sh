#!/usr/bin/env bash
#
# Covers: FG-087
# CAPs:   ci.release-via-pr
#
# FG-087 (restored 2026-11-28 after SH-041 mistakenly retired it):
# ci-release.yml promotes dev → main via auto-merge PR, not a direct push.
# Main's classic branch protection requires `resolve-pr` from shepherd-gates
# app 15368, which only fires on pull_request events — so direct pushes
# are structurally blocked. This test guards against another SH-041-style
# regression that would break ci-release again.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-087]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

_wf=".github/workflows/ci-release.yml"
[[ -f "${_wf}" ]] || fail "${_wf} missing"

# Whitespace-normalised view: collapses multi-line continuations so single-
# line grep patterns match across YAML's `run: |` blocks.
_wf_flat=$(tr -s '[:space:]' ' ' < "${_wf}")

# -----------------------------------------------------------------------------
# Section 1 — no direct push to main; uses PR + auto-merge
# -----------------------------------------------------------------------------
say "1. ci-release.yml no longer does a direct push to main"

# Hard rule: no raw `git push origin main` or `git push ... main:...` anywhere.
if grep -nE 'git[[:space:]]+push[[:space:]]+origin[[:space:]]+main([^A-Za-z0-9_-]|$)' "${_wf}"; then
  fail "ci-release.yml must not do 'git push origin main' — use PR + auto-merge."
fi
if grep -nE 'git[[:space:]]+push[[:space:]].*(^|[[:space:]])main:' "${_wf}"; then
  fail "ci-release.yml must not do any 'git push … main:…' ref-update — use PR + auto-merge."
fi
pass "no direct push to main"

grep -qE 'gh pr create .*--base main' <<<"${_wf_flat}" \
  || fail "ci-release.yml must call 'gh pr create --base main'"
pass "gh pr create --base main present"

grep -qE 'gh pr merge .*--auto' <<<"${_wf_flat}" \
  || fail "ci-release.yml must enable auto-merge via 'gh pr merge --auto'"
pass "gh pr merge --auto present"

# -----------------------------------------------------------------------------
# Section 2 — dev-CI-green assertion preserved
# -----------------------------------------------------------------------------
say "2. pre-flight dev-CI-green assertion still present"

grep -q 'Acceptance aggregate (all green)' "${_wf}" \
  || fail "ci-release.yml must still check the Acceptance aggregate (all green) status"
grep -q 'Lint & verify (PR + push-to-dev)' "${_wf}" \
  || fail "ci-release.yml must still check the Lint & verify status"
pass "both pre-flight assertions present"

# -----------------------------------------------------------------------------
# Section 3 — reuses an existing open release PR
# -----------------------------------------------------------------------------
say "3. workflow reuses an existing open dev→main PR instead of duplicating"

grep -qE 'gh pr list .*--base main .*--head|gh pr list .*--head .*--base main' <<<"${_wf_flat}" \
  || fail "ci-release.yml must look up an existing open dev→main PR before creating one"
pass "existing-PR lookup present"

# -----------------------------------------------------------------------------
# Section 4 — tags v<VERSION> on main HEAD after merge
# -----------------------------------------------------------------------------
say "4. after merge, tags v<VERSION> on main"

# VERSION file is the tag source (SH-029 convention, preserved through the
# PR flow transition).
[[ -f VERSION ]] || fail "VERSION file missing — ci-release can't determine tag"

grep -q 'VERSION' "${_wf}" \
  || fail "ci-release.yml must read VERSION for the tag"
grep -qE 'git tag "?v\$[{(]VERSION|git tag "v\$' <<<"${_wf_flat}" \
  || fail "ci-release.yml must run 'git tag v<VERSION>'"
grep -qE 'git push origin "?v\$' <<<"${_wf_flat}" \
  || fail "ci-release.yml must push the v<VERSION> tag"
pass "VERSION-driven tag step present"

# -----------------------------------------------------------------------------
# Section 5 — CAP + INDEX bookkeeping
# -----------------------------------------------------------------------------
say "5. CAP + INDEX reflect the PR-based flow"

grep -q '^### ci\.release-via-pr' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### ci.release-via-pr"
# Guard against the SH-041 pattern: CAP text that still points at release.yml
# after that file no longer exists.
if grep -A4 '^### ci\.release-via-pr' docs/specs/CAPABILITIES.md | grep -q 'release\.yml' \
   && ! grep -A4 '^### ci\.release-via-pr' docs/specs/CAPABILITIES.md | grep -q 'ci-release\.yml'; then
  fail "ci.release-via-pr CAP still references release.yml (deleted by SH-041); should point at ci-release.yml"
fi
pass "CAP references the live workflow"

grep -q 'FG-087' docs/stories/INDEX.md \
  || fail "docs/stories/INDEX.md missing FG-087 row"
pass "INDEX includes FG-087"

# -----------------------------------------------------------------------------
# Section 6 — Makefile ci-release target is consistent with the PR flow
# -----------------------------------------------------------------------------
say "6. Makefile ci-release target delegates to the workflow (no stale direct-push)"

# Reject the pre-SH-041 direct-push Makefile recipe shape. If Makefile
# contains BOTH `ci-release-promote:` AND `git push origin main`, it's the
# retired direct-push shape.
if grep -qE 'ci-release-promote:' Makefile && grep -qE 'git[[:space:]]+push[[:space:]]+origin[[:space:]]+main' Makefile; then
  fail "Makefile ci-release-promote still has 'git push origin main' — retired shape; see ci-release.yml"
fi
pass "Makefile ci-release target is PR-flow-compatible"

# -----------------------------------------------------------------------------
# Section 7 — actionlint clean (if installed)
# -----------------------------------------------------------------------------
say "7. actionlint clean on ci-release.yml (if installed locally)"
if command -v actionlint >/dev/null 2>&1; then
  actionlint "${_wf}" \
    || fail "actionlint failed on ci-release.yml"
  pass "actionlint clean"
else
  pass "actionlint not installed — skipping (CI still runs it)"
fi

echo
echo "FG-087 acceptance: all sections passed."
