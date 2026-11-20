#!/usr/bin/env bash
#
# Covers: FG-071
# CAPs:   build.builder-migrated, arch.builder-tier-images

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-071]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

BUILDERS=(python-trixie go-trixie node-trixie zig-trixie)

# --- (1) 4 renames + old flat paths gone ---
say "1. 4 builders moved to images/builder/, flat forge-builder-* paths gone"
for b in "${BUILDERS[@]}"; do
  test -d "images/builder/$b" || fail "images/builder/$b missing"
done
_flat=$(find images -maxdepth 1 -type d -name 'forge-builder-*' 2>/dev/null | wc -l)
[[ "${_flat}" -eq 0 ]] || fail "flat images/forge-builder-* still exists (${_flat} found)"
pass "4 builders at builder/, 0 flat"

# --- (2) explicit repo: fields present ---
say "2. each nested image.yaml declares explicit repo: builder/<lang>-trixie"
for b in "${BUILDERS[@]}"; do
  grep -qE "^repo: builder/${b}$" "images/builder/$b/image.yaml" \
    || fail "images/builder/$b/image.yaml missing 'repo: builder/$b'"
done
pass "all 4 have explicit repo: builder/<lang>-trixie"

# --- (3) no Dockerfile uses FORGE_BUILDER_* ARG ---
say "3. no Dockerfile declares ARG FORGE_BUILDER_*"
_bad=$(grep -lE '^ARG\s+FORGE_BUILDER' images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null || true)
[[ -z "${_bad}" ]] || { echo "${_bad}" >&2; fail "stale FORGE_BUILDER_ ARGs remain"; }
# And new BUILDER_<LANG>_REF appears in multiple consumers
_new=$(grep -lE '^ARG\s+BUILDER_(PYTHON|GO|NODE|ZIG)_REF' images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null | wc -l)
[[ "${_new}" -ge 11 ]] || fail "only ${_new} Dockerfiles use BUILDER_<LANG>_REF (want ≥ 11)"
pass "no stale FORGE_BUILDER; ${_new} Dockerfiles use BUILDER_<LANG>_REF"

# --- (3b) no Dockerfile references flat forge-builder-* GHCR path ---
_flatghcr=$(grep -lE 'ghcr\.io/bboortz/forge-builder-' images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null || true)
[[ -z "${_flatghcr}" ]] || { echo "${_flatghcr}" >&2; fail "Dockerfiles still reference ghcr.io/bboortz/forge-builder-*"; }
# And new builder/* path appears
_newpath=$(grep -lE 'ghcr\.io/bboortz/builder/(python|go|node|zig)-trixie' images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null | wc -l)
[[ "${_newpath}" -ge 11 ]] || fail "only ${_newpath} Dockerfiles reference builder/* GHCR paths (want ≥ 11)"
pass "no flat forge-builder-* GHCR paths; ${_newpath} Dockerfiles reference builder/*"

# --- (4) discover-images.sh builders mode = 4 entries ---
say "4. discover-images.sh builders returns 4 entries under builder/"
out=$(bash scripts/discover-images.sh builders)
got=$(echo "${out}" | jq '.include | length')
[[ "${got}" -eq 4 ]] || fail "builders mode returned ${got} entries (want 4)"
_nonprefixed=$(echo "${out}" | jq -r '.include[] | select(.image_dir | startswith("builder/") | not) | .image_dir' 2>&1)
[[ -z "${_nonprefixed}" ]] || { echo "${_nonprefixed}" >&2; fail "discover-images returned builders not under builder/"; }
pass "4 entries, all under builder/"

# --- (5) verify-no-upstream-drift _EXPECTED=6 (unchanged) ---
say "5. verify-no-upstream-drift stays at _EXPECTED=6"
grep -qE '^_EXPECTED=6$' scripts/verify-no-upstream-drift.sh \
  || fail "verify-no-upstream-drift _EXPECTED must be 6 (unchanged)"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails on current fleet"
pass "drift guard green at _EXPECTED=6"

# --- (6) conformance lint green + Rule 7 recognizes new builder paths ---
say "6. verify-dockerfile-conformance green + builder paths recognized"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "conformance lint failed"
grep -q 'builder/python-trixie\|builder/.lang.-trixie\|"builder/' scripts/verify-dockerfile-conformance.py \
  || fail "conformance script doesn't recognize builder/ paths"
pass "conformance green + builder/ paths wired"

# --- (7) dep graph L2 subgraph renders 4 builders with normalized ids ---
say "7. dep graph L2 has all 4 builders with builder_<lang>_trixie ids"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
for b in "${BUILDERS[@]}"; do
  id="builder_${b//-/_}"
  echo "${_graph}" | awk '/subgraph L2_builders/,/^    end$/' \
    | grep -qE "${id}\\[\"builder/${b}\"\\]:::builder" \
    || fail "L2 subgraph missing ${id}['builder/${b}']:::builder"
done
pass "all 4 builders present in L2 with normalized ids"

# --- (8) CAPs documented + traceability green ---
say "8. CAPABILITIES documents the new CAPs + traceability green"
grep -q '^### build.builder-migrated' docs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### build.builder-migrated"
grep -q '^### arch.builder-tier-images' docs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### arch.builder-tier-images"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
pass "CAPs registered + traceability green"

echo
echo "FG-071 acceptance: all sections passed."
