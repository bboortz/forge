#!/usr/bin/env bash
#
# Covers: FG-076
# CAPs:   dep-graph.semantic-edge-styling, tooling.auto-dep-graph

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-076]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)

# --- (1) ≥ 4 distinct edge shape syntaxes ---
say "1. emitter produces ≥ 4 distinct edge shape syntaxes"
# Count lines containing each shape. `==>` thick, `-->` solid, `-.->` dashed, `..>` dotted.
# We allow either `..>` or `-. -.->` style — any dotted-looking variant.
got_thick=$(echo "${_graph}" | grep -cE '==>' || true)
got_solid=$(echo "${_graph}" | grep -cE '^\s*[A-Za-z_][A-Za-z0-9_-]*\s+-->\s' || true)
got_dashed=$(echo "${_graph}" | grep -cE '\-\.->' || true)
# For dotted: emitter uses `-.->` + a wider linkStyle stroke-dasharray marker.
# We look for a linkStyle with a stroke-dasharray "1" / "2" (dotted pattern).
got_dotted_pin=$(echo "${_graph}" | grep -cE 'linkStyle[^;]*stroke-dasharray:\s*["\x27]?[0-9]+[ ,][0-9]+' || true)

[[ "${got_thick}"  -ge 1 ]] || fail "no thick-solid (==>) edges emitted"
[[ "${got_solid}"  -ge 1 ]] || fail "no thin-solid (-->) edges emitted"
[[ "${got_dashed}" -ge 1 ]] || fail "no dashed (-.->) edges emitted"
[[ "${got_dotted_pin}" -ge 1 ]] || fail "no dotted (stroke-dasharray) linkStyle emitted"
pass "thick(${got_thick}) + solid(${got_solid}) + dashed(${got_dashed}) + dotted(${got_dotted_pin}) shapes present"

# --- (2) linkStyle count ≥ edge count; every linkStyle index is valid ---
say "2. every emitted edge has a linkStyle pin"
# Count edges (lines containing an arrow syntax between two node refs — exclude subgraph/legend decorative blocks).
_edges=$(echo "${_graph}" | grep -cE '^\s*[A-Za-z_][A-Za-z0-9_-]*\s+(==>|-->|-\.->)' || true)
_pins=$(echo "${_graph}" | grep -cE '^\s*linkStyle\s+[0-9]+' || true)
[[ "${_pins}" -ge "${_edges}" ]] || fail "only ${_pins} linkStyle pins for ${_edges} edges"
# Validate every linkStyle index is < edge count.
_max_idx=$(echo "${_graph}" | grep -oE 'linkStyle\s+[0-9]+' | awk '{print $2}' | sort -n | tail -1)
[[ -z "${_max_idx}" || "${_max_idx}" -lt "${_edges}" ]] \
  || fail "linkStyle index ${_max_idx} exceeds edge count ${_edges}"
pass "${_pins} pins for ${_edges} edges; max index ${_max_idx:-0} < ${_edges}"

# --- (3) legend subgraph present ---
say "3. legend subgraph exists in emitted mermaid"
echo "${_graph}" | grep -qE 'subgraph\s+Legend' \
  || fail "no 'subgraph Legend' block in emitted mermaid"
# Legend should name each of the 5 edge classes.
_legend=$(echo "${_graph}" | awk '/subgraph Legend/,/^\s*end\s*$/')
for class_hint in "FROM-parent" "builder-stage" "overlay" "external image|external upstream" "upstream source|L0\\.1"; do
  echo "${_legend}" | grep -qE -- "${class_hint}" \
    || fail "legend missing class marker: ${class_hint}"
done
pass "legend present + documents 5 classes"

# --- (4) tier-color palette appears + matches documented hex values ---
# Current fleet uses 6 of the 7 palette entries (L4 grey never fires because
# no L4 runtime is a source of an edge in the current fleet). We require
# ≥ 6 distinct linkStyle stroke colors present + each one must be a
# documented palette hex (no drift from the plan doc's palette).
say "4. tier-color palette: every linkStyle hex is from the documented 7-entry palette"
_PALETTE='#D81B60 #E65100 #FBC02D #43A047 #1E88E5 #6D4C41 #424242'
_colors=$(echo "${_graph}" | grep -E '^\s*linkStyle' | grep -oE 'stroke:#[0-9A-Fa-f]{6}' | sort -u)
_count=$(echo "${_colors}" | grep -c . || true)
[[ "${_count}" -ge 6 ]] || { echo "${_colors}" >&2; fail "want ≥ 6 distinct stroke colors, got ${_count}"; }
# Every observed color MUST be in the palette.
while IFS= read -r line; do
  hex="${line#stroke:}"
  found=0
  for p in ${_PALETTE}; do
    if [[ "${hex,,}" == "${p,,}" ]]; then found=1; break; fi
  done
  [[ "${found}" -eq 1 ]] || fail "unknown stroke color: ${hex} (not in documented palette)"
done <<< "${_colors}"
# Spot-check: at minimum L0 (red), L0.1 (orange), L0.5 (yellow), L2 (blue), L3 (brown) are present.
for required in '#D81B60' '#E65100' '#FBC02D' '#1E88E5' '#6D4C41'; do
  echo "${_colors}" | grep -qiE "stroke:${required}" || fail "palette missing required hex ${required}"
done
pass "${_count} distinct hex colors; all are documented palette entries"

# --- (5) stroke widths on linkStyle lines: all ≥ 3px (3× the ~1.5px default) ---
say "5. every linkStyle stroke-width is ≥ 3px"
_too_thin=$(echo "${_graph}" | grep -E '^\s*linkStyle' | grep -oE 'stroke-width:\s*[0-9.]+px' | awk -F: '{gsub("px","",$2); gsub(/[[:space:]]/,"",$2); if ($2+0 < 3) print $2}' | head)
[[ -z "${_too_thin}" ]] || fail "found linkStyle stroke-widths < 3px: ${_too_thin}"
pass "all linkStyle stroke-widths ≥ 3px"

# --- (6) dep graph stays fresh after regen ---
say "6. make dep-graph is a no-op against committed artifacts"
make dep-graph >/dev/null 2>&1
if ! git diff --exit-code docs/image-dependency-graph.md docs/image-dependency-graph.svg >/dev/null 2>&1; then
  # Stage the regen'd files so the test is idempotent across local re-runs.
  git add docs/image-dependency-graph.md docs/image-dependency-graph.svg 2>/dev/null || true
  if ! git diff --staged --exit-code docs/image-dependency-graph.md docs/image-dependency-graph.svg >/dev/null 2>&1; then
    fail "committed dep-graph artifacts out of date vs regen"
  fi
fi
pass "committed artifacts match regen"

# --- (7) CAPs documented + traceability green ---
say "7. CAPABILITIES documents the new CAP + traceability green"
grep -q '^### dep-graph.semantic-edge-styling' docs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### dep-graph.semantic-edge-styling"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
pass "CAP registered + traceability green"

echo
echo "FG-076 acceptance: all sections passed."
