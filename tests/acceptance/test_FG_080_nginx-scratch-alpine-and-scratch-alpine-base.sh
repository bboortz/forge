#!/usr/bin/env bash
#
# Covers: FG-080
# CAPs:   image.scratch-alpine-foundation, image.nginx-scratch-alpine

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-080]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) both image dirs exist + Rule 12 ---
say "1. base/scratch-alpine-3 + nginx-scratch-alpine exist; Rule 12 ✓"
test -d images/base/scratch-alpine-3 || fail "images/base/scratch-alpine-3 missing"
test -d images/nginx-scratch-alpine || fail "images/nginx-scratch-alpine missing"
grep -qE '^repo: base/scratch-alpine-3$' images/base/scratch-alpine-3/image.yaml \
  || fail "images/base/scratch-alpine-3/image.yaml missing 'repo: base/scratch-alpine-3'"
# nginx-scratch-alpine depends_on base/scratch-alpine-3 (Rule 12 forge-internal-consumer)
grep -qE '^\s*-\s*base/scratch-alpine-3\s*$' images/nginx-scratch-alpine/image.yaml \
  || fail "nginx-scratch-alpine/image.yaml must declare depends_on base/scratch-alpine-3"
# Final-stage FROM of base/scratch-alpine-3 must be `scratch`
final_from=$(awk 'toupper($1) == "FROM" { last = $2 } END { print last }' images/base/scratch-alpine-3/Dockerfile)
[[ "${final_from}" == "scratch" ]] || fail "base/scratch-alpine-3 final FROM is '${final_from}', want 'scratch'"
pass "both dirs present; Rule 12 satisfied; base/* FROMs scratch"

# --- (2) both build + smokes pass ---
say "2. both images build + their smokes pass"
bash scripts/build-image.sh base/scratch-alpine-3 >/dev/null \
  || fail "scripts/build-image.sh base/scratch-alpine-3 failed"
bash scripts/build-image.sh nginx-scratch-alpine >/dev/null \
  || fail "scripts/build-image.sh nginx-scratch-alpine failed"
docker image inspect forge-local/base/scratch-alpine-3:3 >/dev/null \
  || fail "forge-local/base/scratch-alpine-3:3 did not materialize"
docker image inspect forge-local/nginx-scratch-alpine:latest >/dev/null \
  || fail "forge-local/nginx-scratch-alpine:latest did not materialize"
for s in images/base/scratch-alpine-3/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
for s in images/nginx-scratch-alpine/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
pass "both built + smokes green"

# --- (3) verify-dockerfile-conformance green (including Rule 12 on scratch-alpine-3) ---
say "3. verify-dockerfile-conformance green"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "verify-dockerfile-conformance failed"
pass "conformance green"

# --- (4) BASE_SCRATCH_ALPINE_REF registered in _KNOWN_REF_ARGS ---
say "4. BASE_SCRATCH_ALPINE_REF in _KNOWN_REF_ARGS"
grep -qE '^\s*"BASE_SCRATCH_ALPINE_REF"' scripts/verify-dockerfile-conformance.py \
  || fail "BASE_SCRATCH_ALPINE_REF not in _KNOWN_REF_ARGS"
pass "ARG name registered"

# --- (5) _EXPECTED stays ≥ 7 (FG-080 didn't bump; later FGs may have) ---
say "5. verify-no-upstream-drift _EXPECTED ≥ 7 (FG-080's new images FROM forge-rooted)"
_actual=$(awk -F= '/^_EXPECTED=/ {print $2; exit}' scripts/verify-no-upstream-drift.sh)
[[ "${_actual}" -ge 7 ]] \
  || fail "verify-no-upstream-drift _EXPECTED must be >= 7 (got: ${_actual})"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails"
pass "drift guard green at ${_actual} (≥ 7)"

# --- (6) dep graph: both nodes present + overlay edge from base/scratch-alpine-3 ---
say "6. dep graph: base/scratch-alpine-3 in L3, nginx-scratch-alpine in L4 with overlay edge"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${_graph}" | awk '/subgraph L3_baseline/,/^\s*end\s*$/' \
  | grep -qE 'base_scratch_alpine_3\["base/scratch-alpine-3"\]:::baseline' \
  || fail "L3 subgraph missing base_scratch_alpine_3"
echo "${_graph}" | awk '/subgraph L4_runtimes/,/^\s*end\s*$/' \
  | grep -qE 'nginx-scratch-alpine' \
  || fail "L4 subgraph missing nginx-scratch-alpine"
# Overlay edge: nginx-scratch-alpine COPYs from base/scratch-alpine-3 → dashed edge
echo "${_graph}" | grep -qE 'base_scratch_alpine_3 -\.-> nginx-scratch-alpine' \
  || fail "dep graph missing overlay edge base_scratch_alpine_3 -.-> nginx-scratch-alpine"
pass "both nodes + overlay edge present"

# --- (7) nginx serves HTTP 200 (end-to-end container test) ---
say "7. nginx-scratch-alpine serves HTTP 200 on /"
bash images/nginx-scratch-alpine/tests/smoke_serves_http.sh \
  || fail "nginx-scratch-alpine smoke_serves_http failed"
pass "nginx responds with HTTP 200"

# --- (8) CAPs + traceability ---
say "8. CAPs documented + traceability green"
for cap in image.scratch-alpine-foundation image.nginx-scratch-alpine; do
  grep -q "^### ${cap}" docs/specs/CAPABILITIES.md \
    || fail "CAPABILITIES missing ### ${cap}"
done
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability failed"
pass "CAPs registered + traceability green"

echo
echo "FG-080 acceptance: all sections passed."
