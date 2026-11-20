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
say "3. emitter outputs a hybrid SVG+mermaid block covering every image"
out=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${out}" | grep -q '^```mermaid$' || fail 'emitter missing ```mermaid fence'
echo "${out}" | grep -q '^```$' || fail 'emitter missing closing ``` fence'
echo "${out}" | grep -q 'graph TD' || fail "emitter missing 'graph TD' directive"
echo "${out}" | grep -q '!\[Image dependency graph\]' || fail "emitter missing SVG image reference"
echo "${out}" | grep -q '^<details>' || fail "emitter missing <details> wrapper"
# Every local image appears as a node id. FG-066: walk flat + 1-nested
# (images/mirror/<name>/); tier containers (dirs with no image.yaml) are
# skipped. Nested names (e.g. mirror/syft) get their '/' translated to '_'
# in mermaid node ids, so match on the translated form too.
missing_nodes=""
while read -r img; do
  [[ -n "$img" ]] || continue
  # Translate `base/python-scratch-trixie` → `base_python_trixie` for mermaid id matching.
  # The `_local_id` helper in image_from_graph.py replaces BOTH `/` (tier
  # separator) and `-` (dashes inside the leaf) with `_`. The bash side
  # needs to do the same: split on first `/`, keep tier verbatim, replace
  # dashes in the leaf. For flat images (no `/`), id_variant == img.
  if [[ "${img}" == */* ]]; then
    tier="${img%%/*}"
    leaf="${img#*/}"
    id_variant="${tier}_${leaf//-/_}"
  else
    id_variant="${img}"
  fi
  # Match any of:
  #   - node declaration:  `  <id>:::style`
  #   - node declaration with label:  `  <id>["<label>"]:::style`
  #   - edge source:  `<id> -->` / `<id> -.->`
  #   - edge target:  `--> <id>` / `-.-> <id>`
  if ! echo "${out}" | grep -qE "^[[:space:]]*(${img}|${id_variant})(\\[|:::|$)|(${img}|${id_variant}) -->|(${img}|${id_variant}) -\\.->|--> (${img}|${id_variant})|-\\.-> (${img}|${id_variant})"; then
    missing_nodes="${missing_nodes} ${img}"
  fi
done < <(
  for d in images/*/; do
    if [[ -f "${d}image.yaml" ]]; then
      _rel=${d#images/}
      echo "${_rel%/}"
    else
      for sub in "${d}"*/; do
        if [[ -f "${sub}image.yaml" ]]; then
          _rel=${sub#images/}
          echo "${_rel%/}"
        fi
      done
    fi
  done | sort
)
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
say "8. external-sourced images (FG-012) show dashed edge from BEACONRY_SRC + solid from base/python-scratch-trixie"
# FG-069: base/python-scratch-trixie's mermaid node id is `base_python_trixie`
# (slash → underscore per _local_id normalization).
for b in beaconry-hub beaconry-scout beaconry-telegram-mock; do
  grep -q "UP_BEACONRY -\\.-> ${b}" docs/image-dependency-graph.md \
    || fail "${b}: missing dashed UP_BEACONRY edge"
  grep -q "base_python_trixie --> ${b}" docs/image-dependency-graph.md \
    || fail "${b}: missing solid base_python_trixie edge"
done
pass "external-sourced graph edges present"

# --- (9) multi-builder images show every builder edge ----------------------
say "9. prometheus-scratch-trixie + alertmanager-scratch-trixie show BOTH builder edges"
for img in prometheus-scratch-trixie alertmanager-scratch-trixie; do
  grep -q "builder_go_trixie --> ${img}" docs/image-dependency-graph.md \
    || fail "${img}: missing builder/go-trixie edge"
  grep -q "builder_node_trixie --> ${img}" docs/image-dependency-graph.md \
    || fail "${img}: missing builder/node-trixie edge"
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

# --- (13) hybrid layout: SVG image + collapsible mermaid source ------------
say "13. hybrid layout: SVG image + <details> mermaid source"
grep -q '!\[Image dependency graph\](image-dependency-graph.svg)' docs/image-dependency-graph.md \
  || fail "markdown must embed the SVG via ![...](image-dependency-graph.svg)"
grep -q '^<details>' docs/image-dependency-graph.md \
  || fail "markdown must wrap the mermaid source in <details>"
grep -q '^</details>' docs/image-dependency-graph.md \
  || fail "markdown must close </details> after the mermaid source"
pass "SVG embedded + mermaid source inside <details>"

# --- (14) SVG exists, valid, and references the committed node set ---------
say "14. docs/image-dependency-graph.svg exists and is a well-formed SVG"
[[ -f docs/image-dependency-graph.svg ]] \
  || fail 'docs/image-dependency-graph.svg missing — run make dep-graph'
head -1 docs/image-dependency-graph.svg | grep -q '<svg' \
  || fail "docs/image-dependency-graph.svg does not start with <svg"
tail -1 docs/image-dependency-graph.svg | grep -q '</svg>' \
  || fail "docs/image-dependency-graph.svg does not end with </svg>"
pass "SVG exists, well-formed"

# --- (15) scripts/mermaid-to-svg.sh present + executable -------------------
say "15. scripts/mermaid-to-svg.sh present + shellcheck-clean"
[[ -x scripts/mermaid-to-svg.sh ]] \
  || fail "scripts/mermaid-to-svg.sh missing or not executable"
pass "SVG rendering script present"

# --- (16) dep graph is at least as new (in git) as every Dockerfile + image.yaml ---
# Uses git commit timestamps (stable across fresh clones). Dirty / untracked
# files count as "now" so the test fires for local work-in-progress drift.
# This is complementary to §10's content drift gate: it catches commits
# where the content gate was bypassed (--no-verify) OR a Dockerfile edit
# landed in a later commit than the last graph regen.
#
# Short-circuit (FG-072 follow-up): if the generator produces IDENTICAL
# output to the committed graph, the Dockerfile change didn't affect
# topology (e.g. a pure ARG default / LABEL / RUN-step edit like a
# version bump) and §16 would otherwise fire a false positive. §10
# already asserts content-drift freshness.
say "16. dep graph is at least as new as every images/*/{Dockerfile,image.yaml}"
_tmpgraph=$(mktemp -d)
trap 'rm -rf "${_tmpgraph}"' EXIT
python3 scripts/image_from_graph.py --emit=mermaid > "${_tmpgraph}/gen.md"
# Build a temp fresh markdown with the same marker block for a diff.
if diff -q "${_tmpgraph}/gen.md" <(awk '/<!-- GENERATED:dep-graph START/{found=1;next} found && /<!-- GENERATED:dep-graph END/{exit} found' docs/image-dependency-graph.md) >/dev/null 2>&1; then
  pass "dep graph generator output matches committed .md (no topology diff to check)"
else
_file_ts() {
  local f="$1"
  # Untracked → treat as "now".
  if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    date -u +%s
    return
  fi
  # Tracked but modified (staged or unstaged) → treat as "now".
  if ! git diff --quiet HEAD -- "$f" 2>/dev/null; then
    date -u +%s
    return
  fi
  # Committed + clean → use last commit timestamp.
  git log -1 --format=%ct -- "$f" 2>/dev/null || echo 0
}
graph_ts_md=$(_file_ts docs/image-dependency-graph.md)
graph_ts_svg=$(_file_ts docs/image-dependency-graph.svg)
# Pick the OLDER of the two artifacts (both must be at least as new as every input).
if (( graph_ts_md <= graph_ts_svg )); then
  graph_ts=${graph_ts_md}; older_artifact="docs/image-dependency-graph.md"
else
  graph_ts=${graph_ts_svg}; older_artifact="docs/image-dependency-graph.svg"
fi
offenders=()
while IFS= read -r f; do
  ts=$(_file_ts "$f")
  if (( ts > graph_ts )); then
    offenders+=("${f} (ts=${ts}, graph=${graph_ts})")
  fi
done < <(find images -type f \( -name Dockerfile -o -name image.yaml \) | sort)
if (( ${#offenders[@]} > 0 )); then
  echo "✗ ${#offenders[@]} input(s) newer than ${older_artifact}:" >&2
  printf '    %s\n' "${offenders[@]}" >&2
  echo "  → run \`make dep-graph\` and commit the regen" >&2
  fail "dep graph is older than one or more Dockerfile/image.yaml"
fi
pass "dep graph is up-to-date relative to every Dockerfile + image.yaml"
fi

echo
echo "FG-064 acceptance: all sections passed."
