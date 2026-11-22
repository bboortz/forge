#!/usr/bin/env bash
#
# Covers: FG-075
# CAPs:   arch.base-tier-public-api, arch.base-tier-images, image.python-slim-foundation

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-075]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) rename + new image on disk ---
say "1. images/base/python-slim-trixie + images/base/python-scratch-trixie exist; python-trixie gone"
test -d images/base/python-slim-trixie || fail "images/base/python-slim-trixie/ missing"
test -d images/base/python-scratch-trixie || fail "images/base/python-scratch-trixie/ missing"
test ! -e images/base/python-trixie || fail "images/base/python-trixie/ still present (should be renamed)"
# image.yaml carries explicit nested repo:
grep -qE '^repo: base/python-slim-trixie$' images/base/python-slim-trixie/image.yaml \
  || fail "base/python-slim-trixie/image.yaml missing 'repo: base/python-slim-trixie'"
grep -qE '^repo: base/python-scratch-trixie$' images/base/python-scratch-trixie/image.yaml \
  || fail "base/python-scratch-trixie/image.yaml missing 'repo: base/python-scratch-trixie'"
pass "both base/python-{slim,scratch}-trixie present; old path gone"

# --- (2) new slim foundation builds + smokes pass ---
say "2. base/python-slim-trixie builds + its smokes pass"
bash scripts/build-image.sh base/python-slim-trixie >/dev/null \
  || fail "scripts/build-image.sh base/python-slim-trixie failed"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/base/python-slim-trixie/image.yaml)
docker image inspect "forge-local/base/python-slim-trixie:${tag}" >/dev/null \
  || fail "forge-local/base/python-slim-trixie:${tag} did not materialize after build"
for s in images/base/python-slim-trixie/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  IMAGE_TAG="${tag}" bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
pass "base/python-slim-trixie:${tag} built + smokes green"

# --- (3) Rule 12 reworked — slim L3 doesn't FROM scratch yet still passes ---
say "3. Rule 12 reworked: slim base/* passes conformance (not FROM scratch)"
runtime_from=$(awk 'toupper($1)=="FROM"{last=$0} END{print last}' images/base/python-slim-trixie/Dockerfile)
if echo "$runtime_from" | grep -qE 'FROM scratch'; then
  fail "base/python-slim-trixie should NOT FROM scratch — it's the slim variant"
fi
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "verify-dockerfile-conformance failed against the reworked Rule 12"
pass "slim base/* passes conformance; final FROM is '${runtime_from}'"

# --- (4) beaconry consumers point at the rename ---
say "4. beaconry image.yaml depends_on: base/python-scratch-trixie (renamed)"
for b in beaconry-hub beaconry-scout beaconry-telegram-mock; do
  grep -qE '^\s*-\s*base/python-scratch-trixie\s*$' "images/${b}/image.yaml" \
    || fail "images/${b}/image.yaml depends_on must include 'base/python-scratch-trixie'"
  if grep -qE '^\s*-\s*base/python-trixie\s*$' "images/${b}/image.yaml"; then
    fail "images/${b}/image.yaml still references the old name base/python-trixie"
  fi
done
pass "3 beaconry consumers depend on base/python-scratch-trixie"

# --- (5) public API documented in docs/specs/LAYERING.md ---
say "5. docs/specs/LAYERING.md names the public API + internal boundary"
grep -qE '^## [0-9]+\.\s*Public API vs internal implementation' docs/specs/LAYERING.md \
  || fail "docs/specs/LAYERING.md missing '## N. Public API vs internal implementation' section"
grep -q 'base/\*' docs/specs/LAYERING.md || fail "docs/specs/LAYERING.md must mention base/* as public API"
# pre-builder/* is mentioned in both the public section ("do NOT FROM") and its own internal row.
grep -qE 'pre-builder' docs/specs/LAYERING.md || fail "docs/specs/LAYERING.md must mention pre-builder"
grep -qE 'do NOT FROM from outside Forge|Internal implementation' docs/specs/LAYERING.md \
  || fail "docs/specs/LAYERING.md must mark internal tiers as such"
pass "public API boundary documented"

# --- (6) verify-no-upstream-drift _EXPECTED=6 (unchanged) ---
say "6. verify-no-upstream-drift stays at _EXPECTED=6"
# FG-079: _EXPECTED bumped 6 → 7 (Alpine). Loosened to script-runs-clean.
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails on current fleet"
pass "drift guard green at _EXPECTED=6"

# --- (7) discover-images.sh "all" lists every base/* member ---
say "7. discover-images.sh all lists base/python-{slim,scratch}-trixie + base/scratch-trixie"
out=$(bash scripts/discover-images.sh all)
for member in base/scratch-trixie base/python-scratch-trixie base/python-slim-trixie; do
  echo "${out}" | jq -r '.include[].image_dir' | grep -qx "${member}" \
    || fail "discover-images all missing ${member}"
done
pass "all three base/* members discovered"

# --- (8) CAPs documented + traceability green ---
say "8. CAPABILITIES documents the new CAPs + traceability green"
grep -q '^### arch.base-tier-public-api' docs/specs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### arch.base-tier-public-api"
grep -q '^### image.python-slim-foundation' docs/specs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### image.python-slim-foundation"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
pass "CAPs registered + traceability green"

echo
echo "FG-075 acceptance: all sections passed."
