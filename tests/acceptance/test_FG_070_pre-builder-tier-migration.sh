#!/usr/bin/env bash
#
# Covers: FG-070
# CAPs:   build.pre-builder-migrated, arch.pre-builder-tier-images

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-070]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

PRE_BUILDERS=(debian-slim-trixie debian-slim-sid go-slim-trixie node-slim-trixie python-slim-trixie ubuntu-slim-noble zig-slim-trixie)

# --- (1) 7 renames + old paths gone ---
say "1. 7 pre-builders moved to images/pre-builder/, flat paths gone"
for p in "${PRE_BUILDERS[@]}"; do
  test -d "images/pre-builder/$p" || fail "images/pre-builder/$p missing"
  test ! -e "images/$p" || fail "images/$p still exists (flat path should be gone)"
done
pass "7 pre-builders at pre-builder/, 0 flat"

# --- (2) explicit repo: fields present ---
say "2. each nested image.yaml declares explicit repo: pre-builder/<name>"
for p in "${PRE_BUILDERS[@]}"; do
  grep -qE "^repo: pre-builder/${p}$" "images/pre-builder/$p/image.yaml" \
    || fail "images/pre-builder/$p/image.yaml missing 'repo: pre-builder/$p'"
done
pass "all 7 have explicit repo: pre-builder/<name>"

# --- (3) 8 consumer ARG defaults updated ---
say "3. no Dockerfile references ghcr.io/bboortz/<flat-pre-builder>"
_bad=$(grep -lE "ghcr\\.io/bboortz/(debian-slim-trixie|debian-slim-sid|go-slim-trixie|node-slim-trixie|python-slim-trixie|ubuntu-slim-noble|zig-slim-trixie):" images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null \
  | grep -v "pre-builder/" || true)
[[ -z "${_bad}" ]] || { echo "${_bad}" >&2; fail "stale ARG defaults still reference flat pre-builder paths"; }
# Also assert new path appears in multiple consumers.
_new=$(grep -lE "ghcr\\.io/bboortz/pre-builder/(debian|go|node|python|ubuntu|zig)-slim" images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null | wc -l)
[[ "${_new}" -ge 8 ]] || fail "only ${_new} Dockerfiles reference pre-builder/ paths (want ≥ 8)"
pass "no stale refs; ${_new} Dockerfiles use pre-builder/* paths"

# --- (4) discover-images.sh pre-builders mode ≥ 7 entries ---
# FG-070 originally locked pre-builders = 7. FG-079 adds pre-builder/alpine-3.
# Assert ≥ 7 + all entries under pre-builder/.
say "4. discover-images.sh pre-builders returns ≥ 7 under pre-builder/"
out=$(bash scripts/discover-images.sh pre-builders)
got=$(echo "${out}" | jq '.include | length')
[[ "${got}" -ge 7 ]] || fail "pre-builders mode returned ${got} entries (want ≥ 7)"
# Every entry starts with pre-builder/
_nonprefixed=$(echo "${out}" | jq -r '.include[] | select(.image_dir | startswith("pre-builder/") | not) | .image_dir' 2>&1)
[[ -z "${_nonprefixed}" ]] || { echo "${_nonprefixed}" >&2; fail "discover-images returned entries not under pre-builder/"; }
pass "${got} entries, all under pre-builder/"

# --- (5) verify-no-upstream-drift clean (FG-070 doesn't change the count) ---
# FG-070 shipped with _EXPECTED=6. FG-079 bumped to 7 (Alpine). The
# invariant FG-070 cares about — 7 pre-builders published at their new
# paths — is not count-locked here.
say "5. verify-no-upstream-drift clean (pre-builders moved paths, not count)"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails on current fleet"
pass "drift guard still clean"

# --- (6) conformance lint green + language-family invariant uses new paths ---
say "6. verify-dockerfile-conformance green + language-family expects pre-builder/ sibling"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "conformance lint failed"
grep -q 'pre-builder/{lang}-slim-trixie\|pre-builder/<lang>-slim-trixie\|pre-builder/.lang.-slim' scripts/verify-dockerfile-conformance.py \
  || fail "language-family invariant doesn't expect pre-builder/ sibling"
pass "conformance green + sibling check updated"

# --- (7) dep graph L1 subgraph renders 7 pre-builders with normalized ids ---
say "7. dep graph L1 has all 7 pre-builders with pre-builder_<leaf> ids"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
for p in "${PRE_BUILDERS[@]}"; do
  id="pre-builder_${p//-/_}"
  echo "${_graph}" | awk '/subgraph L1_prebuilders/,/^    end$/' \
    | grep -qE "${id}\\[\"pre-builder/${p}\"\\]:::prebuilder" \
    || fail "L1 subgraph missing ${id}['pre-builder/${p}']:::prebuilder"
done
pass "all 7 pre-builders present in L1 with normalized ids"

# --- (8) FG-074 coordination held at draft ---
say "8. FG-074 (homelab coordination) remains at draft — NOT solved here"
test -f docs/stories/FG-074-homelab-pre-builder-consumer-migration.md \
  || fail "FG-074 story missing"
_status=$(awk '/^status:/{print $2; exit}' docs/stories/FG-074-homelab-pre-builder-consumer-migration.md)
[[ "${_status}" == "draft" ]] \
  || fail "FG-074 status is '${_status}' — should still be draft (paired PR waits for forge publish)"
pass "FG-074 held at draft per user direction"

# --- (9) CAPs documented + traceability green ---
say "9. CAPABILITIES documents the new CAPs + traceability green"
grep -q '^### build.pre-builder-migrated' docs/specs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### build.pre-builder-migrated"
grep -q '^### arch.pre-builder-tier-images' docs/specs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### arch.pre-builder-tier-images"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
pass "CAPs registered + traceability green"

echo
echo "FG-070 acceptance: all sections passed."
