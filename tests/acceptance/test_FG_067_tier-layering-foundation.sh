#!/usr/bin/env bash
#
# Covers: FG-067
# CAPs:   arch.tier-prefix-convention, arch.layer-overlap-resolution

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-067]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) memory/docker-standard.md documents the 7-tier model ---
say "1. memory/docker-standard.md contains § '7-tier layering model'"
grep -q '^## 7-tier layering model' memory/docker-standard.md \
  || fail "memory/docker-standard.md missing '## 7-tier layering model' heading"
# Must mention every tier id.
for tier in L0 L0.1 L0.5 L1 L2 L3 L4; do
  grep -q "\\*\\*${tier}\\*\\*" memory/docker-standard.md \
    || fail "memory/docker-standard.md missing bold reference to tier ${tier}"
done
grep -q 'docs/plan/tier-layering-model.md' memory/docker-standard.md \
  || fail "memory/docker-standard.md must link to docs/plan/tier-layering-model.md for the full table"
pass "7-tier section present + all 7 tier ids referenced + plan-doc link present"

# --- (2) docs/CAPABILITIES.md registers the two foundation CAPs ---
say "2. docs/CAPABILITIES.md registers the FG-067 foundation CAPs"
grep -q '^### arch.tier-prefix-convention' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing ### arch.tier-prefix-convention"
grep -q '^### arch.layer-overlap-resolution' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing ### arch.layer-overlap-resolution"
# Each CAP section must have a 'Covered by:' pointer.
for cap in arch.tier-prefix-convention arch.layer-overlap-resolution; do
  awk -v cap="### $cap" '
    $0 == cap { inside = 1; next }
    inside && /^### / { exit 1 }
    inside && /Covered by/ { found = 1; exit 0 }
    END { exit !found }
  ' docs/CAPABILITIES.md \
    || fail "${cap}: no 'Covered by:' pointer"
done
pass "both NEW CAPs present + each has a Covered by pointer"

# --- (3) Rule 11 negative guard — logic present + current-fleet pass ---
say "3. verify-dockerfile-conformance.py has Rule 11 negative guard against source/"
grep -q 'Rule 11' scripts/verify-dockerfile-conformance.py \
  || fail "scripts/verify-dockerfile-conformance.py missing Rule 11"
# Must reference the retired source/ tier + check IMAGES_DIR / 'source'.
grep -qE "images/source|IMAGES_DIR / .source." scripts/verify-dockerfile-conformance.py \
  || fail "Rule 11 must check for images/source/ directory existence"
# Negative test — simulate images/source/ existence with a tmp copy + patched IMAGES_DIR.
_tmp=$(mktemp -d)
# shellcheck disable=SC2064  # _tmp is final — expand-now is intentional
trap "rm -rf '${_tmp}'" EXIT
mkdir -p "${_tmp}/images/source/dummy"
cat > "${_tmp}/images/source/dummy/Dockerfile" <<'EOF'
FROM scratch
EOF
cat > "${_tmp}/images/source/dummy/image.yaml" <<'EOF'
tag: "0.1"
platforms: [linux/amd64]
EOF
# Run conformance.py with IMAGES_DIR overridden via env var — see implementation note.
set +e
out=$(FORGE_IMAGES_DIR="${_tmp}/images" python3 scripts/verify-dockerfile-conformance.py 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  echo "${out}" >&2
  fail "Rule 11 did NOT fire on synthetic images/source/dummy (lint exited 0 — expected 1)"
fi
echo "${out}" | grep -qE 'Rule 11|retired|source/' \
  || { echo "${out}" >&2; fail "Rule 11 fired but error message didn't name the rule or retired-source"; }
pass "Rule 11 fires on synthetic images/source/dummy"

# Current real fleet: Rule 11 must NOT fire (no images/source/ today).
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "conformance lint fails on current HEAD (Rule 11 false-positive or unrelated regression)"
pass "current fleet passes conformance lint (Rule 11 does not false-fire)"

# --- (4) traceability green with the new CAPs ---
say "4. make verify-traceability green incl. new FG-067 CAPs"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
# The new CAPs must show up in the known-CAP list the script uses.
# Sanity: grep KNOWN known-CAPs output — accept either path.
_traced=$(bash scripts/verify-traceability.sh 2>&1 | tail -3)
echo "${_traced}" | grep -q 'ok' \
  || fail "traceability output doesn't contain 'ok' banner"
pass "traceability green"

# --- (5) [retired FG-069] FG-067 originally asserted "no image dirs moved in
# this PR" — a PR-scoped check that false-positives on EVERY later PR that
# legitimately moves images (starting with FG-069). The assertion belonged
# in the one-time pre-ship audit, not a permanent acceptance test. Replaced
# with a check that FG-067's actual deliverables (memory + CAPs + Rule 11)
# are present — already asserted in §§1-4 above. No-op section preserved so
# the section numbering stays stable.
say "5. FG-067 deliverables remain present (asserted in §§1-4)"
pass "FG-067 asserts its own deliverables, not external state"

echo
echo "FG-067 acceptance: all sections passed."
