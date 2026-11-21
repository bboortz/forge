#!/usr/bin/env bash
#
# Covers: FG-079
# CAPs:   arch.alpine-pre-builder, image.alpine-foundation, arch.base-tier-public-api

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-079]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) image dirs exist with explicit repo: ---
say "1. pre-builder/alpine-3 + base/alpine-3 exist with explicit repo:"
test -d images/pre-builder/alpine-3 || fail "images/pre-builder/alpine-3 missing"
test -d images/base/alpine-3 || fail "images/base/alpine-3 missing"
grep -qE '^repo: pre-builder/alpine-3$' images/pre-builder/alpine-3/image.yaml \
  || fail "pre-builder/alpine-3/image.yaml missing 'repo: pre-builder/alpine-3'"
grep -qE '^repo: base/alpine-3$' images/base/alpine-3/image.yaml \
  || fail "base/alpine-3/image.yaml missing 'repo: base/alpine-3'"
pass "both images present with explicit repo:"

# --- (2) verify-no-upstream-drift bumped 6 → 7 ---
say "2. verify-no-upstream-drift _EXPECTED=7 (bumped from 6)"
grep -qE '^_EXPECTED=7$' scripts/verify-no-upstream-drift.sh \
  || fail "verify-no-upstream-drift _EXPECTED must be 7"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails"
pass "drift guard at _EXPECTED=7"

# --- (3) both images build + smokes pass ---
say "3. both images build + their smokes pass"
bash scripts/build-image.sh pre-builder/alpine-3 >/dev/null \
  || fail "scripts/build-image.sh pre-builder/alpine-3 failed"
bash scripts/build-image.sh base/alpine-3 >/dev/null \
  || fail "scripts/build-image.sh base/alpine-3 failed"
tag_pre=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/pre-builder/alpine-3/image.yaml)
tag_base=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/base/alpine-3/image.yaml)
docker image inspect "forge-local/pre-builder/alpine-3:${tag_pre}" >/dev/null \
  || fail "forge-local/pre-builder/alpine-3:${tag_pre} did not materialize"
docker image inspect "forge-local/base/alpine-3:${tag_base}" >/dev/null \
  || fail "forge-local/base/alpine-3:${tag_base} did not materialize"
for s in images/pre-builder/alpine-3/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  IMAGE_TAG="${tag_pre}" bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
for s in images/base/alpine-3/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  IMAGE_TAG="${tag_base}" bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
pass "both built + smokes green"

# --- (4) no builder/alpine-* ---
say "4. no builder/alpine-* exists (OS family, not language family)"
if ls -d images/builder/alpine-* 2>/dev/null | grep -q .; then
  fail "images/builder/alpine-* exists — Alpine is an OS family, no builder expected"
fi
if grep -qE 'alpine' scripts/discover-images.sh 2>/dev/null \
   && bash scripts/discover-images.sh builders 2>&1 | jq -r '.include[].image_dir' | grep -q alpine; then
  fail "discover-images.sh builders mode contains an alpine image"
fi
pass "no builder/alpine-*; L2 Alpine not spawned"

# --- (5) ALPINE_REF + BASE_ALPINE_REF in _KNOWN_REF_ARGS ---
say "5. ALPINE_REF + BASE_ALPINE_REF registered in _KNOWN_REF_ARGS"
grep -qE '^\s*"ALPINE_REF"' scripts/verify-dockerfile-conformance.py \
  || fail "ALPINE_REF not in _KNOWN_REF_ARGS"
grep -qE '^\s*"BASE_ALPINE_REF"' scripts/verify-dockerfile-conformance.py \
  || fail "BASE_ALPINE_REF not in _KNOWN_REF_ARGS"
pass "both ARG names registered"

# --- (6) conformance + traceability green ---
say "6. verify-dockerfile-conformance + traceability green"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "verify-dockerfile-conformance failed"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability failed"
pass "conformance + traceability green"

# --- (7) dep graph: alpine nodes in L1 + L3 subgraphs ---
say "7. dep graph: pre-builder/alpine-3 in L1, base/alpine-3 in L3"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${_graph}" | awk '/subgraph L1_prebuilders/,/^\s*end\s*$/' \
  | grep -qE 'pre-builder_alpine_3\["pre-builder/alpine-3"\]:::prebuilder' \
  || fail "L1 subgraph missing pre-builder_alpine_3"
echo "${_graph}" | awk '/subgraph L3_baseline/,/^\s*end\s*$/' \
  | grep -qE 'base_alpine_3\["base/alpine-3"\]:::baseline' \
  || fail "L3 subgraph missing base_alpine_3"
pass "both nodes present with normalized ids"

# --- (8) CAPs documented ---
say "8. CAPs documented + traceability green"
for cap in arch.alpine-pre-builder image.alpine-foundation; do
  grep -q "^### ${cap}" docs/CAPABILITIES.md \
    || fail "CAPABILITIES missing ### ${cap}"
done
pass "CAPs registered"

echo
echo "FG-079 acceptance: all sections passed."
