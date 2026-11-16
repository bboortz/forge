#!/usr/bin/env bash
#
# Covers: FG-064
# CAPs:   tooling.auto-dep-graph, tooling.dockerfile-conformance

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-064]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) scripts exist ------------------------------------------------------
say "1. conformance lint + mermaid emitter scripts present + executable"
[[ -x scripts/verify-dockerfile-conformance.py ]] || fail "scripts/verify-dockerfile-conformance.py missing or not executable"
[[ -x scripts/image_from_graph.py ]] || fail "scripts/image_from_graph.py missing or not executable"
pass "both scripts in place"

# --- (2) conformance lint passes on the live fleet --------------------------
say "2. every images/*/Dockerfile conforms to FG-064 convention"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "scripts/verify-dockerfile-conformance.py fails on current HEAD"
pass "fleet conforms"

# --- (3) mermaid emitter runs + output is well-formed -----------------------
say "3. emitter outputs a mermaid fenced block covering every image"
out=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${out}" | grep -q '^```mermaid$' || fail 'emitter missing ```mermaid fence'
echo "${out}" | tail -1 | grep -q '^```$' || fail 'emitter missing closing ``` fence'
echo "${out}" | grep -q 'graph TD' || fail "emitter missing 'graph TD' directive"
# Every local image dir appears as a node id.
missing_nodes=""
while read -r img; do
  [[ -n "$img" ]] || continue
  if ! echo "${out}" | grep -qE "^[[:space:]]*${img}:::|${img} -->|${img} -\\.->|--> ${img}|-\\.-> ${img}"; then
    missing_nodes="${missing_nodes} ${img}"
  fi
done < <(find images -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ -z "${missing_nodes}" ]] || fail "emitter missing nodes:${missing_nodes}"
pass "emitter output is well-formed + covers every image"

# --- (4) idempotent: running --write twice leaves the file identical --------
say "4. make dep-graph is idempotent"
make dep-graph >/dev/null
sha_a=$(sha256sum docs/image-dependency-graph.md | awk '{print $1}')
make dep-graph >/dev/null
sha_b=$(sha256sum docs/image-dependency-graph.md | awk '{print $1}')
[[ "${sha_a}" == "${sha_b}" ]] \
  || fail "make dep-graph is not idempotent (sha changed ${sha_a} → ${sha_b})"
pass "idempotent"

# --- (5) GENERATED markers preserved + narrative outside markers untouched --
say "5. generator respects the GENERATED markers"
grep -q "<!-- GENERATED:dep-graph START" docs/image-dependency-graph.md \
  || fail "START marker missing after regen"
grep -q "<!-- GENERATED:dep-graph END -->" docs/image-dependency-graph.md \
  || fail "END marker missing after regen"
# Facts section must still exist outside the markers.
grep -q "^## Facts behind the graph" docs/image-dependency-graph.md \
  || fail "Facts narrative section was lost"
grep -q "^## Regenerating" docs/image-dependency-graph.md \
  || fail "Regenerating narrative section was lost"
pass "markers + narrative preserved"

# --- (6) 5-layer subgraph structure ----------------------------------------
say "6. output enforces the 5-layer subgraph structure"
for sg in L0_upstream L1_prebuilders L2_builders L3_baseline L4_runtimes; do
  grep -q "subgraph ${sg}\[" docs/image-dependency-graph.md \
    || fail "subgraph ${sg} missing"
done
# Subgraph order: L0 before L1 before L2 before L3 before L4.
awk '/subgraph L[0-4]_/ {print NR, $0}' docs/image-dependency-graph.md \
  | awk 'BEGIN{p=-1} {match($0, /L([0-4])_/, m); if (m[1] <= p) exit 1; p=m[1]} END{exit 0}' \
  || fail "subgraphs are not in L0 → L4 order"
pass "5 subgraphs present, in order"

# --- (7) no intra-layer edges ----------------------------------------------
say "7. no intra-layer FROM edges in the current fleet"
# Already implied by the conformance lint passing in §2; re-assert explicitly.
if python3 scripts/verify-dockerfile-conformance.py 2>&1 | grep -q 'intra-layer'; then
  fail "conformance lint reported an intra-layer edge"
fi
pass "no intra-layer edges"

# --- (8) external-sourced beaconry resolved via image.yaml depends_on -------
say "8. external-sourced images (FG-012) show dashed edge from BEACONRY_SRC + solid from python-scratch-trixie"
for b in beaconry-hub beaconry-scout beaconry-telegram-mock; do
  grep -q "UP_BEACONRY -\\.-> ${b}" docs/image-dependency-graph.md \
    || fail "${b}: missing dashed UP_BEACONRY edge"
  grep -q "python-scratch-trixie --> ${b}" docs/image-dependency-graph.md \
    || fail "${b}: missing solid python-scratch-trixie edge"
done
pass "external-sourced graph edges present"

# --- (9) multi-builder images show every builder edge ----------------------
say "9. prometheus-scratch-trixie + alertmanager-scratch-trixie show BOTH builder edges"
for img in prometheus-scratch-trixie alertmanager-scratch-trixie; do
  grep -q "forge-builder-go-trixie --> ${img}" docs/image-dependency-graph.md \
    || fail "${img}: missing forge-builder-go-trixie edge"
  grep -q "forge-builder-node-trixie --> ${img}" docs/image-dependency-graph.md \
    || fail "${img}: missing forge-builder-node-trixie edge"
done
pass "dual-builder edges present"

# --- (10) make verify-dep-graph-fresh gates stale commits ------------------
say "10. make verify-dep-graph-fresh green after a regen+stage cycle"
make dep-graph >/dev/null
# Stage the regen'd file so git diff --exit-code (vs index) is clean.
git add docs/image-dependency-graph.md 2>/dev/null || true
make verify-dep-graph-fresh >/dev/null \
  || fail "make verify-dep-graph-fresh failed even after regen+stage"
pass "drift gate green when file is fresh"

# --- (11) conformance lint is wired into pre-commit + test-fast ------------
say "11. verify-dockerfile-conformance + dep-graph-fresh wired into pre-commit + test-fast"
grep -q 'id: verify-dockerfile-conformance' .pre-commit-config.yaml \
  || fail ".pre-commit-config.yaml missing verify-dockerfile-conformance hook"
grep -q 'id: dep-graph-fresh' .pre-commit-config.yaml \
  || fail ".pre-commit-config.yaml missing dep-graph-fresh hook"
grep -q 'verify-dockerfile-conformance' Makefile \
  || fail "Makefile missing verify-dockerfile-conformance target"
grep -q 'verify-dep-graph-fresh' Makefile \
  || fail "Makefile missing verify-dep-graph-fresh target"
grep -q 'test-fast:.*verify-dockerfile-conformance.*verify-dep-graph-fresh' Makefile \
  || fail "test-fast must chain both verify-dockerfile-conformance and verify-dep-graph-fresh"
pass "wired into pre-commit + test-fast (CI picks it up via make test-fast)"

# --- (12) legend / classDef / palette preserved -----------------------------
say "12. classDef palette matches the hand-maintained one"
for cls in upstream prebuilder builder baseline slim scratch external; do
  grep -q "classDef ${cls}" docs/image-dependency-graph.md \
    || fail "classDef ${cls} missing from regenerated block"
done
pass "7 classDef entries present"

echo
echo "FG-064 acceptance: all sections passed."
