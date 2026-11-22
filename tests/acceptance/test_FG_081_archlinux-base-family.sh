#!/usr/bin/env bash
#
# Covers: FG-081
# CAPs:   arch.archlinux-pre-builder, image.archlinux-foundation, arch.base-tier-public-api

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-081]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) image dirs exist with explicit repo: ---
say "1. pre-builder/archlinux + base/archlinux exist with explicit repo:"
test -d images/pre-builder/archlinux || fail "images/pre-builder/archlinux missing"
test -d images/base/archlinux || fail "images/base/archlinux missing"
grep -qE '^repo: pre-builder/archlinux$' images/pre-builder/archlinux/image.yaml \
  || fail "pre-builder/archlinux/image.yaml missing 'repo: pre-builder/archlinux'"
grep -qE '^repo: base/archlinux$' images/base/archlinux/image.yaml \
  || fail "base/archlinux/image.yaml missing 'repo: base/archlinux'"
pass "both images present with explicit repo:"

# --- (2) verify-no-upstream-drift bumped 7 → 8 ---
say "2. verify-no-upstream-drift _EXPECTED=8 (bumped from 7)"
grep -qE '^_EXPECTED=8$' scripts/verify-no-upstream-drift.sh \
  || fail "verify-no-upstream-drift _EXPECTED must be 8"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails"
pass "drift guard at _EXPECTED=8"

# --- (3) both images build + smokes pass ---
say "3. both images build + their smokes pass"
bash scripts/build-image.sh pre-builder/archlinux >/dev/null \
  || fail "scripts/build-image.sh pre-builder/archlinux failed"
bash scripts/build-image.sh base/archlinux >/dev/null \
  || fail "scripts/build-image.sh base/archlinux failed"
tag_pre=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/pre-builder/archlinux/image.yaml)
tag_base=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/base/archlinux/image.yaml)
docker image inspect "forge-local/pre-builder/archlinux:${tag_pre}" >/dev/null \
  || fail "forge-local/pre-builder/archlinux:${tag_pre} did not materialize"
docker image inspect "forge-local/base/archlinux:${tag_base}" >/dev/null \
  || fail "forge-local/base/archlinux:${tag_base} did not materialize"
for s in images/pre-builder/archlinux/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  IMAGE_TAG="${tag_pre}" bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
for s in images/base/archlinux/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  IMAGE_TAG="${tag_base}" bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
pass "both built + smokes green"

# --- (4) no builder/archlinux-* ---
say "4. no builder/archlinux-* exists (OS family, not language family)"
# shellcheck disable=SC2144  # glob-against-array check is idiomatic here
_arch_builder_dirs=(images/builder/archlinux-*)
if [[ -d "${_arch_builder_dirs[0]}" ]]; then
  fail "images/builder/archlinux-* exists — Arch is an OS family, no builder expected"
fi
if bash scripts/discover-images.sh builders 2>&1 | jq -r '.include[].image_dir' | grep -q archlinux; then
  fail "discover-images.sh builders mode contains an archlinux image"
fi
pass "no builder/archlinux-*; L2 Arch not spawned"

# --- (5) ARCHLINUX_REF + BASE_ARCHLINUX_REF in _KNOWN_REF_ARGS ---
say "5. ARCHLINUX_REF + BASE_ARCHLINUX_REF registered in _KNOWN_REF_ARGS"
grep -qE '^\s*"ARCHLINUX_REF"' scripts/verify-dockerfile-conformance.py \
  || fail "ARCHLINUX_REF not in _KNOWN_REF_ARGS"
grep -qE '^\s*"BASE_ARCHLINUX_REF"' scripts/verify-dockerfile-conformance.py \
  || fail "BASE_ARCHLINUX_REF not in _KNOWN_REF_ARGS"
pass "both ARG names registered"

# --- (6) conformance + traceability green ---
say "6. verify-dockerfile-conformance + traceability green"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "verify-dockerfile-conformance failed"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability failed"
pass "conformance + traceability green"

# --- (7) dep graph: arch nodes in L1 + L3 subgraphs ---
say "7. dep graph: pre-builder/archlinux in L1, base/archlinux in L3"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${_graph}" | awk '/subgraph L1_prebuilders/,/^\s*end\s*$/' \
  | grep -qE 'pre-builder_archlinux\["pre-builder/archlinux"\]:::prebuilder' \
  || fail "L1 subgraph missing pre-builder_archlinux"
echo "${_graph}" | awk '/subgraph L3_baseline/,/^\s*end\s*$/' \
  | grep -qE 'base_archlinux\["base/archlinux"\]:::baseline' \
  || fail "L3 subgraph missing base_archlinux"
pass "both nodes present with normalized ids"

# --- (8) CAPs documented ---
say "8. CAPs documented + traceability green"
for cap in arch.archlinux-pre-builder image.archlinux-foundation; do
  grep -q "^### ${cap}" docs/specs/CAPABILITIES.md \
    || fail "CAPABILITIES missing ### ${cap}"
done
pass "CAPs registered"

echo
echo "FG-081 acceptance: all sections passed."
