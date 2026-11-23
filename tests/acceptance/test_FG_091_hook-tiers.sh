#!/usr/bin/env bash
#
# Covers: FG-091 / SH-042
# CAPs:   tier.hook-commit, tier.hook-push
#
# FG-091 (forge-side of shepherd SH-042): canonical fleet-tier Makefile
# wrappers `hook-commit` (~15 s budget) + `hook-push` (~2 min budget).
# Forge keeps its native step names inside repo-local COMMIT_STEPS /
# PUSH_STEPS variables (lint + verify-sid-pins + verify-traceability for
# commit; check-smart for push). No step renames; no workflow edits.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-091]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — hook-commit + hook-push declared .PHONY
# -----------------------------------------------------------------------------
say "1. .PHONY includes hook-commit + hook-push"

# Fold logical .PHONY lines (handle line continuations) and search for tokens.
phony=$(awk '/^\.PHONY:/{flag=1} flag{printf "%s ", $0; if ($0 !~ /\\$/) {print ""; flag=0}}' Makefile)
printf '%s' "${phony}" | grep -Fq 'hook-commit' \
  || fail ".PHONY does not declare hook-commit"
pass ".PHONY declares hook-commit"
printf '%s' "${phony}" | grep -Fq 'hook-push' \
  || fail ".PHONY does not declare hook-push"
pass ".PHONY declares hook-push"

# -----------------------------------------------------------------------------
# Section 2 — dry-run resolves without executing recipes
# -----------------------------------------------------------------------------
say "2. make -n hook-commit + make -n hook-push resolve (rc 0)"

make -n hook-commit >/dev/null 2>&1 || fail "make -n hook-commit returned non-zero"
pass "make -n hook-commit rc 0"
make -n hook-push >/dev/null 2>&1 || fail "make -n hook-push returned non-zero"
pass "make -n hook-push rc 0"

# -----------------------------------------------------------------------------
# Section 3 — hook-commit dry-run invokes forge's commit steps
# -----------------------------------------------------------------------------
say "3. hook-commit dry-run expands lint + verify-sid-pins + verify-traceability"

out_commit=$(make -n hook-commit 2>&1)

# lint target recipe expands to hadolint / shellcheck / yamllint markers.
grep -Fq 'hadolint'                         <<<"${out_commit}" \
  || fail "hook-commit dry-run missing lint marker (hadolint)"
pass "hook-commit → lint (hadolint marker present)"

grep -Fq 'scripts/verify-sid-pins.sh'       <<<"${out_commit}" \
  || fail "hook-commit dry-run missing verify-sid-pins.sh"
pass "hook-commit → verify-sid-pins"

grep -Fq 'scripts/verify-traceability.sh'   <<<"${out_commit}" \
  || fail "hook-commit dry-run missing verify-traceability.sh"
pass "hook-commit → verify-traceability"

# -----------------------------------------------------------------------------
# Section 4 — hook-push dry-run invokes forge's push steps
# -----------------------------------------------------------------------------
say "4. hook-push dry-run expands check-smart (smart-check.sh)"

out_push=$(make -n hook-push 2>&1)
grep -Fq 'scripts/smart-check.sh'           <<<"${out_push}" \
  || fail "hook-push dry-run missing smart-check.sh marker"
pass "hook-push → check-smart (smart-check.sh)"

# -----------------------------------------------------------------------------
# Section 5 — docs link resolves (story + plan)
# -----------------------------------------------------------------------------
say "5. story + plan docs exist"

[[ -f docs/stories/FG-091-hook-tiers.md ]] \
  || fail "missing docs/stories/FG-091-hook-tiers.md"
pass "docs/stories/FG-091-hook-tiers.md present"

[[ -f docs/plan/FG-091-hook-tiers-plan.md ]] \
  || fail "missing docs/plan/FG-091-hook-tiers-plan.md"
pass "docs/plan/FG-091-hook-tiers-plan.md present"

# -----------------------------------------------------------------------------
# Section 6 — CAPs registered
# -----------------------------------------------------------------------------
say "6. docs/specs/CAPABILITIES.md registers the two FG-091 CAPs"

grep -Eq '^### tier\.hook-commit' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### tier.hook-commit"
pass "tier.hook-commit registered"

grep -Eq '^### tier\.hook-push' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### tier.hook-push"
pass "tier.hook-push registered"

# -----------------------------------------------------------------------------
# Section 7 — INDEX lists FG-091
# -----------------------------------------------------------------------------
say "7. docs/stories/INDEX.md lists FG-091"
grep -Fq 'FG-091' docs/stories/INDEX.md \
  || fail "docs/stories/INDEX.md missing FG-091 row"
pass "INDEX includes FG-091"

echo
echo "FG-091 acceptance: all sections passed."
