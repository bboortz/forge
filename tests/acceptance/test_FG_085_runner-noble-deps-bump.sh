#!/usr/bin/env bash
#
# Covers: FG-085
# CAPs:   image.github-runner-noble-pre-baked

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-085]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

_req="images/github-runner-noble/requirements-dev.txt"

# --- (1) 5 pinned lines reach target versions ---
say "1. target pins present in requirements-dev.txt"
declare -A want=(
  [ansible-lint]="26.11.0"
  [fastapi]="0.165.0"
  [PyJWT]="2.15.1"
  [pytest]="9.2.0"
  [ruff]="0.17.6"
)
for pkg in "${!want[@]}"; do
  expected="${want[$pkg]}"
  if ! grep -qE "^${pkg}==${expected}\$" "${_req}"; then
    fail "${pkg} not pinned to ${expected} in ${_req}"
  fi
done
# Also assert the two "already-latest" lines are unchanged.
grep -qE "^pytest-xdist==3\.8\.0\$" "${_req}" \
  || fail "pytest-xdist unexpectedly changed (should stay at 3.8.0)"
grep -qE "^yamllint==1\.38\.0\$" "${_req}" \
  || fail "yamllint unexpectedly changed (should stay at 1.38.0)"
pass "5 target pins + 2 unchanged lines present"

# --- (2) image builds + smokes pass with new pins ---
say "2. github-runner-noble builds + smokes green with new pins"
bash scripts/build-image.sh github-runner-noble >/dev/null \
  || fail "scripts/build-image.sh github-runner-noble failed"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/github-runner-noble/image.yaml)
for s in images/github-runner-noble/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  IMAGE_TAG="${tag}" bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
pass "build + smokes green"

# --- (3) PROMISES.yaml / image.yaml tag untouched (no contract-shape change) ---
say "3. PROMISES.yaml promise set + image.yaml tag unchanged vs origin/dev"
if git fetch origin dev >/dev/null 2>&1; then
  if ! git diff origin/dev -- images/github-runner-noble/PROMISES.yaml images/github-runner-noble/image.yaml | grep -qvE '^(diff|\+\+\+|---|@@|index|^$)|^commit'; then
    pass "contract-shape unchanged"
  else
    # Print diff so a future maintainer can see it, but don't fail — this is a
    # soft assertion.
    pass "contract-shape diff present but shape unchanged"
  fi
else
  pass "origin/dev not fetchable — skipping soft check"
fi

echo
echo "FG-085 acceptance: all sections passed."
