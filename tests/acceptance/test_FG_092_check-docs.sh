#!/usr/bin/env bash
#
# Covers: FG-092 / SH-055
# CAPs:   tier.check-docs
#
# FG-092 (forge-side of shepherd SH-055): canonical fleet-tier Makefile
# wrapper `check-docs` delegates to forge's three doc/metadata-drift
# gates — verify-traceability, verify-sid-pins, verify-promises-version-bump.
# No step renames; no new logic; wired into PUSH_STEPS + ci-branch so pre-push
# + CI both back the gate.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-092]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — check-docs declared .PHONY
# -----------------------------------------------------------------------------
say "1. .PHONY includes check-docs"

phony=$(awk '/^\.PHONY:/{flag=1} flag{printf "%s ", $0; if ($0 !~ /\\$/) {print ""; flag=0}}' Makefile)
printf '%s' "${phony}" | grep -Fq 'check-docs' \
  || fail ".PHONY does not declare check-docs"
pass ".PHONY declares check-docs"

# -----------------------------------------------------------------------------
# Section 2 — check-docs target exists with its delegate chain
# -----------------------------------------------------------------------------
say "2. check-docs target declared with verify-* prerequisites"

grep -qE '^check-docs:' Makefile \
  || fail "check-docs: target not declared in Makefile"
pass "check-docs: target declared"

grep -qE '^check-docs:.*verify-traceability' Makefile \
  || fail "check-docs doesn't declare verify-traceability as prerequisite"
pass "check-docs → verify-traceability"

grep -qE '^check-docs:.*verify-sid-pins' Makefile \
  || fail "check-docs doesn't declare verify-sid-pins as prerequisite"
pass "check-docs → verify-sid-pins"

grep -qE '^check-docs:.*verify-promises-version-bump' Makefile \
  || fail "check-docs doesn't declare verify-promises-version-bump as prerequisite"
pass "check-docs → verify-promises-version-bump"

# -----------------------------------------------------------------------------
# Section 3 — PUSH_STEPS + ci-branch include check-docs
# -----------------------------------------------------------------------------
say "3. PUSH_STEPS + ci-branch include check-docs"

grep -qE '^PUSH_STEPS.*check-docs' Makefile \
  || fail "PUSH_STEPS missing check-docs"
pass "PUSH_STEPS includes check-docs"

grep -qE '^ci-branch:.*check-docs' Makefile \
  || fail "ci-branch missing check-docs"
pass "ci-branch includes check-docs"

# -----------------------------------------------------------------------------
# Section 4 — dry-run resolves without executing recipes
# -----------------------------------------------------------------------------
say "4. make -n check-docs resolves (rc 0)"

make -n check-docs >/dev/null 2>&1 || fail "make -n check-docs returned non-zero"
pass "make -n check-docs rc 0"

# -----------------------------------------------------------------------------
# Section 5 — check-docs dry-run invokes forge's three delegate scripts
# -----------------------------------------------------------------------------
say "5. check-docs dry-run expands to its three delegate scripts"

out=$(make -n check-docs 2>&1)

grep -Fq 'scripts/verify-traceability.sh' <<<"${out}" \
  || fail "check-docs dry-run missing verify-traceability.sh"
pass "check-docs → verify-traceability.sh"

grep -Fq 'scripts/verify-sid-pins.sh' <<<"${out}" \
  || fail "check-docs dry-run missing verify-sid-pins.sh"
pass "check-docs → verify-sid-pins.sh"

grep -Fq 'scripts/verify-promises-version-bump.sh' <<<"${out}" \
  || fail "check-docs dry-run missing verify-promises-version-bump.sh"
pass "check-docs → verify-promises-version-bump.sh"

# -----------------------------------------------------------------------------
# Section 6 — hook-push dry-run now expands check-docs' delegates
# -----------------------------------------------------------------------------
say "6. hook-push dry-run includes check-docs' delegates"

out_push=$(make -n hook-push 2>&1)
grep -Fq 'scripts/verify-traceability.sh' <<<"${out_push}" \
  || fail "hook-push dry-run missing verify-traceability.sh (check-docs not wired?)"
pass "hook-push → check-docs → verify-traceability.sh"

# -----------------------------------------------------------------------------
# Section 7 — docs link resolves (story + plan)
# -----------------------------------------------------------------------------
say "7. story + plan docs exist"

[[ -f docs/stories/FG-092-check-docs.md ]] \
  || fail "missing docs/stories/FG-092-check-docs.md"
pass "docs/stories/FG-092-check-docs.md present"

[[ -f docs/plan/FG-092-check-docs-plan.md ]] \
  || fail "missing docs/plan/FG-092-check-docs-plan.md"
pass "docs/plan/FG-092-check-docs-plan.md present"

# -----------------------------------------------------------------------------
# Section 8 — CAP registered
# -----------------------------------------------------------------------------
say "8. docs/specs/CAPABILITIES.md registers tier.check-docs"

grep -Eq '^### tier\.check-docs' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### tier.check-docs"
pass "tier.check-docs registered"

# -----------------------------------------------------------------------------
# Section 9 — INDEX lists FG-092
# -----------------------------------------------------------------------------
say "9. docs/stories/INDEX.md lists FG-092"
grep -Fq 'FG-092' docs/stories/INDEX.md \
  || fail "docs/stories/INDEX.md missing FG-092 row"
pass "INDEX includes FG-092"

echo
echo "FG-092 acceptance: all sections passed."
