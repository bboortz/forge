#!/usr/bin/env bash
#
# Covers: FG-041
# CAPs:   ci.cosign-pin-drift-gate (NEW),
#         sign.cosign-keyless-oidc (EXT),
#         sign.cosign-local-dev (EXT)
#
# Validates FG-041: cosign pin bumped v2.4.3 → v2.6.5 to patch
# GHSA-fx35-mq7g-6g98 (HIGH verification-bypass). All references
# across workflows + Makefile cite the same version. Drift-gate:
# fails ≤ 7 days before supply-chain.md's review date so the next
# deadline doesn't slip past unnoticed.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-041]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

EXPECTED_PIN="v2.6.5"

# -----------------------------------------------------------------------------
# Section 1 — every cosign reference across the repo pins v2.6.5
# -----------------------------------------------------------------------------
say "1. every cosign version reference pins ${EXPECTED_PIN}"

# References we know about:
#   - .github/workflows/build.yml       (3 publish jobs × cosign:vX.Y.Z)
#   - .github/workflows/nightly.yml     (cosign:vX.Y.Z)
#   - Makefile                          (cosign/releases/download/vX.Y.Z/)
#
# Grep every possible reference shape and assert each matches the pin.
mapfile -t refs < <(
  grep -hoE 'cosign:v[0-9]+\.[0-9]+\.[0-9]+' \
    .github/workflows/*.yml \
    scripts/*.sh 2>/dev/null \
    | sort -u
  grep -hoE 'cosign/releases/download/v[0-9]+\.[0-9]+\.[0-9]+' \
    Makefile 2>/dev/null \
    | sed 's|cosign/releases/download/|cosign:|' \
    | sort -u
)

[[ "${#refs[@]}" -gt 0 ]] || fail "no cosign version references found (grep pattern drift?)"

bad=()
for r in "${refs[@]}"; do
  ver="${r#cosign:}"
  if [[ "${ver}" != "${EXPECTED_PIN}" ]]; then
    bad+=("${r}")
  fi
done

if [[ "${#bad[@]}" -gt 0 ]]; then
  echo "  ✗ expected all cosign pins = ${EXPECTED_PIN}, found divergent:" >&2
  printf '    %s\n' "${bad[@]}" >&2
  exit 1
fi
pass "${#refs[@]} distinct reference(s), all ${EXPECTED_PIN}"

# -----------------------------------------------------------------------------
# Section 2 — memory/supply-chain.md cites v2.6.5 (doc ↔ pin consistency)
# -----------------------------------------------------------------------------
say "2. memory/supply-chain.md cites ${EXPECTED_PIN}"
grep -qF "${EXPECTED_PIN}" memory/supply-chain.md \
  || fail "memory/supply-chain.md does not mention ${EXPECTED_PIN} — doc / pin drift"
pass "supply-chain.md references ${EXPECTED_PIN}"

# -----------------------------------------------------------------------------
# Section 3 — review date parseable + strictly in the future
# -----------------------------------------------------------------------------
say "3. review date in memory/supply-chain.md is parseable + future"
REVIEW_LINE=$(grep -oE 'review due [0-9]{4}-[0-9]{2}-[0-9]{2}' memory/supply-chain.md | head -1)
[[ -n "${REVIEW_LINE}" ]] \
  || fail "no 'review due YYYY-MM-DD' found in memory/supply-chain.md"
REVIEW_DATE="${REVIEW_LINE##* }"

# Testable "today" via env override — lets the drift gate itself be unit-tested.
TODAY="${FG_041_TODAY:-$(date -u +%F)}"
today_epoch=$(date -u -d "${TODAY}" +%s) \
  || fail "FG_041_TODAY=${TODAY} not parseable as YYYY-MM-DD"
review_epoch=$(date -u -d "${REVIEW_DATE}" +%s) \
  || fail "review date ${REVIEW_DATE} not parseable"

if [[ "${review_epoch}" -le "${today_epoch}" ]]; then
  fail "review date ${REVIEW_DATE} is not strictly after today (${TODAY}) — pin has drifted past its deadline. Operator: ship a FG to renew or upgrade the pin."
fi
pass "review date ${REVIEW_DATE} is after today (${TODAY})"

# -----------------------------------------------------------------------------
# Section 4 — DRIFT GATE: fail ≤ 7 days before review date
# -----------------------------------------------------------------------------
say "4. drift gate — ≥ 7 days to review date"
days_remaining=$(( (review_epoch - today_epoch) / 86400 ))

if [[ "${days_remaining}" -le 7 ]]; then
  echo "  ✗ Cosign pin review deadline is in ${days_remaining} day(s) (${REVIEW_DATE})." >&2
  echo "    Decide: renew the pin (bump review date), upgrade to a new v2 point release," >&2
  echo "    or migrate to v3. Edit memory/supply-chain.md → ship a FG → re-run." >&2
  exit 1
fi
pass "${days_remaining} day(s) until review (${REVIEW_DATE}) — drift gate green"

echo
echo "FG-041 acceptance: all sections passed."
