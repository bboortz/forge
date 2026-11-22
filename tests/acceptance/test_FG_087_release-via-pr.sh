#!/usr/bin/env bash
#
# Covers: FG-087
# CAPs:   ci.release-via-pr
#
# FG-087: release.yml promotes dev → main via auto-merge PR (not direct push).
# Preserves main's branch protection; eliminates the loosen-push-restore dance
# that FG-086 was forced to perform.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-087]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

_wf=".github/workflows/release.yml"

# -----------------------------------------------------------------------------
# Section 1 — no direct push to main; uses PR + auto-merge
# -----------------------------------------------------------------------------
say "1. release.yml no longer does a direct push to main"

# Hard rule: no raw `git push origin main` (or any direct push to the main ref)
# anywhere in the workflow. Catch both single- + double-quoted invocations.
if grep -nE 'git[[:space:]]+push[[:space:]]+origin[[:space:]]+main([^A-Za-z0-9_-]|$)' "${_wf}"; then
  fail "release.yml must not do 'git push origin main' — use PR + auto-merge."
fi
if grep -nE 'git[[:space:]]+push[[:space:]].*(^|[[:space:]])main:' "${_wf}"; then
  fail "release.yml must not do any 'git push ... main:...' ref-update — use PR + auto-merge."
fi
pass "no direct push to main"

# Whitespace-normalised contents (collapses line continuations so multi-line
# gh invocations match single-line grep patterns).
_wf_flat=$(tr -s '[:space:]' ' ' < "${_wf}")

grep -qE 'gh pr create .*--base main' <<<"${_wf_flat}" \
  || fail "release.yml must call 'gh pr create --base main'"
pass "gh pr create --base main present"

grep -qE 'gh pr merge .*--auto' <<<"${_wf_flat}" \
  || fail "release.yml must enable auto-merge via 'gh pr merge --auto'"
pass "gh pr merge --auto present"

# -----------------------------------------------------------------------------
# Section 2 — dev-CI-green assertion preserved
# -----------------------------------------------------------------------------
say "2. pre-flight dev-CI-green assertion still present"

grep -q 'Acceptance aggregate (all green)' "${_wf}" \
  || fail "release.yml must still check the Acceptance aggregate (all green) status"
grep -q 'Lint & verify (PR + push-to-dev)' "${_wf}" \
  || fail "release.yml must still check the Lint & verify status"
pass "both pre-flight assertions present"

# -----------------------------------------------------------------------------
# Section 3 — reuses an existing open release PR
# -----------------------------------------------------------------------------
say "3. workflow reuses an existing open dev→main PR instead of creating duplicates"

# We require some flavor of "if a PR dev→main already exists, reuse it".
# Accepted patterns (any one of):
#   - gh pr list --base main --head dev ...
#   - gh pr list --search 'base:main head:dev ...'
#   - gh api ... pulls ... head=dev base=main
grep -qE 'gh pr list .*--base main .*--head|gh pr list .*--head .*--base main|head=dev.*base=main|base=main.*head=dev' <<<"${_wf_flat}" \
  || fail "release.yml must look up an existing open dev→main PR before creating one"
pass "existing-PR lookup present"

# -----------------------------------------------------------------------------
# Section 4 — CAP ci.release-via-pr registered
# -----------------------------------------------------------------------------
say "4. docs/specs/CAPABILITIES.md registers ci.release-via-pr"
grep -q '^### ci\.release-via-pr' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### ci.release-via-pr"
pass "CAP registered"

# -----------------------------------------------------------------------------
# Section 5 — INDEX reflects FG-087
# -----------------------------------------------------------------------------
say "5. docs/stories/INDEX.md lists FG-087"
grep -q 'FG-087' docs/stories/INDEX.md \
  || fail "docs/stories/INDEX.md missing FG-087 row"
pass "INDEX includes FG-087"

# -----------------------------------------------------------------------------
# Section 6 — actionlint happy with the rewritten workflow (if installed)
# -----------------------------------------------------------------------------
say "6. actionlint clean on release.yml (if installed locally)"
if command -v actionlint >/dev/null 2>&1; then
  actionlint "${_wf}" \
    || fail "actionlint failed on release.yml"
  pass "actionlint clean"
else
  pass "actionlint not installed — skipping (CI still runs it)"
fi

echo
echo "FG-087 acceptance: all sections passed."
