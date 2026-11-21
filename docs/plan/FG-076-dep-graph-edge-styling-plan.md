# FG-076 — Plan: dep-graph edges — thicker lines + principled shape+color vocabulary

**Story**: [`docs/stories/FG-076-dep-graph-edge-styling.md`](../stories/FG-076-dep-graph-edge-styling.md)
**Status**: ready → shipped
**Branch**: `feat/FG-076-dep-graph-edge-styling`

## Design delta

`scripts/image_from_graph.py` gains a 5-class edge taxonomy. Every edge the emitter produces maps to exactly one class and carries a (shape, color, width) tuple. The output mermaid source gains a Legend subgraph + a block of `linkStyle` directives (one per edge, indexed in emission order) that pin the rendered stroke color + stroke-width so GitHub's SVG rendering is deterministic.

Edge classes (shape → color → width):

| # | Class | Shape | Width | Color source |
|---|---|---|---|---|
| 1 | FROM-parent (final-stage, content-bearing) | `==>` thick | 5px | tier-of-source palette |
| 2 | FROM builder-stage (content, but copy-only in child) | `-->` solid | 4px | tier-of-source palette |
| 3 | COPY --from overlay | `-.->` dashed | 4px | tier-of-source palette |
| 4 | External upstream image (L0 → L1/exempt L4) | `==>` thick | 5px | **red** `#D81B60` (fixed) |
| 5 | L0.1 upstream source | `..>` dotted (long dasharray) | 3px | **orange** `#E65100` (fixed) |

Tier-of-source color palette (Okabe–Ito-adjacent, Material 600 shades; colorblind-safe):

| Source tier | Hex |
|---|---|
| L0 external image | `#D81B60` red |
| L0.1 external source | `#E65100` orange |
| L0.5 `mirror/*` | `#FBC02D` yellow |
| L1 `pre-builder/*` | `#43A047` green |
| L2 `builder/*` | `#1E88E5` blue |
| L3 `base/*` | `#6D4C41` brown |
| L4 runtime | `#424242` dark grey |

Emitter implementation:
- `build_full_graph(...)` already classifies edges into `forward` (solid), `dashed_local`, `upstream_solid`, `upstream_dashed`, and `external`. Reshape the data flow so the emitter walks a single ordered list of `(source, target, class)` tuples.
- For each tuple, emit one mermaid edge line (correct shape per class) + append one `linkStyle N stroke:#HEX,stroke-width:Npx[,stroke-dasharray:D]` line, indexed in emission order.
- Prepend a Legend subgraph that renders the 5 classes as example edges inside a self-contained subgraph. The legend consumes 5 edge indices + the linkStyle indices shift accordingly.

## Alternatives rejected

- **Label the edges instead of coloring them** (`-->|FROM|`, `-.->|OVERLAY|`): mermaid labels clutter dense graphs — every edge gets a floating text box. Rejected for the ≥20 edges-per-node clusters.
- **Collapse builder-stage FROM into regular FROM-parent**: loses the "CVE propagation" distinction that makes the graph useful during audits. The 2 classes are genuinely different semantics.
- **One color for all edges, differentiate only by shape**: 5 shapes get hard to tell apart (dotted vs sparse-dashed vs dashed all read similarly at small sizes). Color is the cheapest reliable differentiator.
- **"Color = tier of target" instead of "tier of source"**: would highlight which tier an image belongs to, but node `:::class` fills already do that. Coloring edges by source answers "where does this trust originate?" which nothing else answers today.

## Breaking changes

None. The emitted mermaid stays semantically compatible (same node ids, same edges, same arrow directions). GitHub renders the new source identically for anyone who was consuming the graph programmatically. Only the rendered visual changes.

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI acceptance suite + visual check on the committed SVG.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` dispatch — fast-forward main from dev
3. `build.yml` doesn't need to run (no image content changes); next 03:00 UTC cron picks up the dep-graph regeneration if any future downstream caring about it exists. External graph consumers see the new styling on their next GitHub render.

## Shipping evidence

Filled at pre-ship audit. All rows ✅ before merge.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: emitter produces ≥ 4 distinct edge classes | `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh:§1` | ✅ |
| Scenario: every edge has a linkStyle pin | `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh:§2` | ✅ |
| Scenario: legend is present | `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh:§3` | ✅ |
| Scenario: tier colors match palette | `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh:§4` | ✅ |
| Scenario: dep graph stays fresh | `make verify-dep-graph-fresh` | ✅ |
| CAP `dep-graph.semantic-edge-styling` | `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh` + `docs/CAPABILITIES.md#dep-graph.semantic-edge-styling` | ✅ |
| CAP `tooling.auto-dep-graph` (EXT) | `docs/CAPABILITIES.md#tooling.auto-dep-graph` | ✅ |
