#!/usr/bin/env bash
#
# Covers: FG-093 / SH-056
# CAPs:   tier.verify-index-status
#
# FG-093 (forge-side of shepherd SH-056): adopt the fleet-canonical
# `verify-index-status` script byte-identical from shepherd + wire it into
# forge's `check-docs` target as a fourth sibling delegate alongside
# `verify-traceability`, `verify-sid-pins`, `verify-promises-version-bump`.
# Closes the specific drift class `verify-traceability` doesn't cover:
# INDEX.md row status ≠ story frontmatter status.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-093]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — script is byte-identical to shepherd's (best-effort if available)
# -----------------------------------------------------------------------------
say "1. scripts/verify-index-status.sh present + executable"

[[ -f scripts/verify-index-status.sh ]] \
  || fail "scripts/verify-index-status.sh missing"
pass "scripts/verify-index-status.sh present"

[[ -x scripts/verify-index-status.sh ]] \
  || fail "scripts/verify-index-status.sh not executable"
pass "scripts/verify-index-status.sh executable"

# Fleet-convention check: script declares SH-056 lineage so a byte-identical
# copy across the fleet is detectable without a network cross-repo compare.
grep -Fq 'SH-056' scripts/verify-index-status.sh \
  || fail "scripts/verify-index-status.sh missing SH-056 lineage header"
pass "scripts/verify-index-status.sh references SH-056 (fleet lineage)"

# If a sibling shepherd checkout exists at ../shepherd/, assert byte identity.
if [[ -f ../shepherd/scripts/verify-index-status.sh ]]; then
  diff -q scripts/verify-index-status.sh ../shepherd/scripts/verify-index-status.sh \
    >/dev/null 2>&1 \
    || fail "scripts/verify-index-status.sh drifted from ../shepherd/scripts/verify-index-status.sh"
  pass "byte-identical to ../shepherd/scripts/verify-index-status.sh"
else
  pass "sibling shepherd checkout absent — byte-identity asserted via SH-056 header only"
fi

# -----------------------------------------------------------------------------
# Section 2 — .PHONY declares verify-index-status
# -----------------------------------------------------------------------------
say "2. .PHONY includes verify-index-status"

phony=$(awk '/^\.PHONY:/{flag=1} flag{printf "%s ", $0; if ($0 !~ /\\$/) {print ""; flag=0}}' Makefile)
printf '%s' "${phony}" | grep -Fq 'verify-index-status' \
  || fail ".PHONY does not declare verify-index-status"
pass ".PHONY declares verify-index-status"

# -----------------------------------------------------------------------------
# Section 3 — verify-index-status target exists and dry-runs cleanly
# -----------------------------------------------------------------------------
say "3. verify-index-status target declared + dry-runs cleanly"

grep -qE '^verify-index-status:' Makefile \
  || fail "verify-index-status: target not declared in Makefile"
pass "verify-index-status: target declared"

make -n verify-index-status >/dev/null 2>&1 \
  || fail "make -n verify-index-status returned non-zero"
pass "make -n verify-index-status rc 0"

out_vi=$(make -n verify-index-status 2>&1)
grep -Fq 'scripts/verify-index-status.sh' <<<"${out_vi}" \
  || fail "make -n verify-index-status missing scripts/verify-index-status.sh reference"
pass "verify-index-status → scripts/verify-index-status.sh"

# -----------------------------------------------------------------------------
# Section 4 — check-docs includes verify-index-status as a fourth sibling
# -----------------------------------------------------------------------------
say "4. check-docs includes verify-index-status as a fourth sibling"

grep -qE '^check-docs:.*verify-index-status' Makefile \
  || fail "check-docs doesn't declare verify-index-status as prerequisite"
pass "check-docs → verify-index-status"

out_cd=$(make -n check-docs 2>&1)
grep -Fq 'scripts/verify-index-status.sh' <<<"${out_cd}" \
  || fail "check-docs dry-run missing verify-index-status.sh"
pass "check-docs → verify-index-status.sh (dry-run)"

# -----------------------------------------------------------------------------
# Section 5 — verify-index-status passes on the current tree
# -----------------------------------------------------------------------------
say "5. verify-index-status passes on the current tree"

./scripts/verify-index-status.sh >/dev/null 2>&1 \
  || fail "./scripts/verify-index-status.sh failed on current tree — sync INDEX.md"
pass "./scripts/verify-index-status.sh clean"

# -----------------------------------------------------------------------------
# Section 6 — CAP registered + bidirectional links present
# -----------------------------------------------------------------------------
say "6. docs/specs/CAPABILITIES.md registers tier.verify-index-status"

grep -Eq '^### tier\.verify-index-status' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### tier.verify-index-status"
pass "tier.verify-index-status registered"

grep -Fq 'tests/acceptance/test_FG_093_verify-index-status.sh' docs/specs/CAPABILITIES.md \
  || fail "CAP entry missing pointer back to this test"
pass "CAP → test pointer present"

# -----------------------------------------------------------------------------
# Section 7 — story + plan docs exist
# -----------------------------------------------------------------------------
say "7. story + plan docs exist"

[[ -f docs/stories/FG-093-verify-index-status.md ]] \
  || fail "missing docs/stories/FG-093-verify-index-status.md"
pass "docs/stories/FG-093-verify-index-status.md present"

[[ -f docs/plan/FG-093-verify-index-status-plan.md ]] \
  || fail "missing docs/plan/FG-093-verify-index-status-plan.md"
pass "docs/plan/FG-093-verify-index-status-plan.md present"

# -----------------------------------------------------------------------------
# Section 8 — INDEX lists FG-093
# -----------------------------------------------------------------------------
say "8. docs/stories/INDEX.md lists FG-093"
grep -Fq 'FG-093' docs/stories/INDEX.md \
  || fail "docs/stories/INDEX.md missing FG-093 row"
pass "INDEX includes FG-093"

echo
echo "FG-093 acceptance: all sections passed."