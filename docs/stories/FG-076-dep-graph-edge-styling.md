---
id: FG-076
slug: dep-graph-edge-styling
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-076 — dep-graph edges: thicker lines, principled shape+color vocabulary

Rework `docs/image-dependency-graph.{md,svg}` so the edges carry visible, principled meaning: thicker strokes, distinct line shapes (solid / dashed / dotted / thick), and a small, enforced color palette. Each shape+color combination resolves to exactly one semantic class — a reader scans the graph and can tell which arrows are "this image IS a derivative of X", "this image overlays artifacts from X", "this image was built from upstream source X", or "this image pulls the external image X" without consulting the legend.

Today every edge is 1 of only 2 mermaid syntaxes — `-->` (solid) or `-.->` (dashed) — both rendered at the default ~1.5px stroke width in a single color. 82 edges in the current graph; the visual signal-to-noise ratio is low, especially in the SVG where edges cross inside the L4 subgraph. Thicker strokes + more shape variants + semantic coloring would make the graph usable as a trust/architecture map at first glance, not just a dot-connecting diagram.

## 9 canonical answers

1. **Who** — Forge maintainers reading the dep graph to reason about blast radius during tier moves; auditors tracing supply chain from L0 upstream down to a published L4 digest; new contributors trying to understand the 7-tier model's instantiation.
2. **When** — Fires whenever someone opens `docs/image-dependency-graph.md` or the SVG on GitHub + wants to answer: "where does this image's trust originate?" Today the answer requires squinting + legend-cross-referencing; after FG-076 it should be visually obvious.
3. **What success looks like** —
   - `scripts/image_from_graph.py` emits ≥ 4 distinct edge shapes (solid, thick-solid, dashed, dotted) mapped to 4 distinct semantic classes.
   - Each edge shape renders at ≥ 2.5px stroke width (currently ~1.5px default).
   - Each edge carries a color that encodes the **tier of the source** (not the target) — the reader instantly sees which tier the trust originates from.
   - A visible legend at the top of the SVG (or a legend subgraph in the mermaid source) names every shape + color combo with its semantic.
   - Zero color/shape combinations are undefined — if a combo appears, it maps to one of the enumerated classes.
   - The emitter emits deterministic `linkStyle` lines (mermaid's edge-styling directive) so the SVG rendering matches intent across CI runs.
4. **Urgency** — Quality-of-life. No CVE pressure, no regression. Moderate: the dep graph gets re-opened during every tier migration, and the current visual density is unnecessarily hostile.
5. **Happy path** —
   1. Enumerate the current edge vocabulary + what each ambiguous solid/dashed means today (§Edge vocabulary below).
   2. Pick 4–6 semantic classes. Assign each a (shape, color) pair.
   3. Extend `scripts/image_from_graph.py` to emit edges with the chosen mermaid syntax + emit matching `linkStyle N stroke:<color>,stroke-width:<N>px;` lines.
   4. Add a legend subgraph at the top of the emitted mermaid so GitHub renderers (that don't execute arbitrary CSS) show it inline.
   5. Regen `docs/image-dependency-graph.md` + `.svg` via `make dep-graph`.
   6. Update `docs/LAYERING.md` §11 to point readers at the legend.
6. **Edge cases / failure modes** —
   - Mermaid's `linkStyle` is index-based; the emitter must track the order of emitted edges to apply the right style. Any reorder breaks the mapping → acceptance test asserts that every edge has a classification + every `linkStyle` references a valid edge index.
   - Colorblind-safe palette: the chosen 4–6 colors must be distinguishable with deuteranopia/protanopia. We default to an Okabe–Ito-ish palette (the 8-color colorblind-friendly set).
   - SVG stroke width scales with viewBox. Mermaid's `stroke-width:4px` is absolute in rendered output but relative to the viewBox when exported; the acceptance test spot-checks the SVG `<path stroke-width=...>` attribute to pin the rendered width.
   - Legend placement: a free-floating subgraph at the top of the mermaid pushes the main graph down. Acceptable; alternative is a sibling detached mini-diagram in the .md file (worse — splits the source of truth).
7. **Out of scope** —
   - Renaming nodes, changing node :::class styling (that's tier-encoded coloring on the boxes — separate from edge coloring).
   - Adding new nodes to the graph (e.g. splitting beaconry's 3 images into separate upstream edges for different VERSION pins).
   - Touching the L0.1 inventory emitter — only `scripts/image_from_graph.py` + its generated artifacts.
   - Any `verify-dockerfile-conformance.py` behavioral change.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh`. The acceptance test parses the generated mermaid, counts distinct shape+color combinations, asserts ≥ 4 classes are populated, asserts every edge is classified, asserts `linkStyle` indices are valid, and asserts the legend is present.
9. **Capabilities delivered or extended** —
   - NEW `dep-graph.semantic-edge-styling` — dep graph edges encode `(from-tier, relationship-kind)` via `(color, shape)` — 4+ classes documented + enforced.
   - EXT `tooling.auto-dep-graph` — extended beyond "it exists + it's fresh" into "it is legible."

## Edge vocabulary — what each class means

The emitter produces edges in 5 semantic classes. Every edge the script emits maps to **exactly one** of these.

| # | Class | Current syntax | Proposed shape | Proposed color | Meaning |
|---|---|---|---|---|---|
| **1** | **FROM (parent inheritance, final-stage)** | `-->` | **thick solid** `==>` | tier-of-source (see below) | The consumer's final-stage FROM resolves to this image. Trust + CVE + stdlib all propagate. The most common edge; the "spine" of the graph. |
| **2** | **FROM (builder-stage only, content discarded)** | `-->` (indistinguishable from #1!) | **thin solid** `-->` | tier-of-source | Multi-stage builder: the consumer FROMs this image to run `pip install` / `go build` / etc., then COPYs artifacts from it and discards the stage. CVEs in the builder do NOT propagate to the runtime; this is the invisible-but-important distinction today's graph loses. |
| **3** | **COPY --from (artifact overlay)** | `-.->` | **dashed** `-.->` | tier-of-source | Consumer brings a subset of this source into its runtime via `COPY --from=<stage> <path>`. Not inheritance — only the named artifact propagates. Current example: `base/scratch-trixie -.-> *` (overlay), `mirror/syft -.-> builder/*` (tool copy). |
| **4** | **External upstream image (L0)** | `-->` (mixed with #1) | **thick solid** `==>` | **red** (external, not-forge-signed) | Consumer (L1 pre-builder / runtime exemption) FROMs an external Docker Hub image. Color-coded red because the trust originates outside Forge's cosign identity. |
| **5** | **Upstream source (L0.1)** | `-.->` (mixed with #3) | **dotted** `-. -.-> .` | **orange** (external source) | Consumer's build-time `git clone` or `curl .tar.xz` of a repo/tarball. Not an image; not a FROM; not a COPY. Separate shape so readers can distinguish "we fetched source X" from "we FROM image X" at a glance. |

## Tier-of-source color palette

Edge color encodes **where the trust originates** — the tier of the source node, not the target. All classes 1–3 use this palette; classes 4+5 override with their external-marker colors.

| Source tier | Color (hex) | Rationale |
|---|---|---|
| L0 external image | `#D81B60` red | Outside Forge's signing boundary |
| L0.1 external source | `#E65100` orange | Build-time fetch, not an image |
| L0.5 `mirror/*` | `#FBC02D` yellow | Forge-signed passthrough of external tool |
| L1 `pre-builder/*` | `#43A047` green | Forge-internal, apt-upgrade layer |
| L2 `builder/*` | `#1E88E5` blue | Forge-internal, dev toolchain |
| L3 `base/*` | `#6D4C41` brown | Forge public API foundation |
| L4 runtime | `#424242` dark grey | Rare source class; shouldn't generally originate edges in the current fleet |

Palette picked from the Okabe–Ito colorblind-friendly set (plus one brown adjustment for L3). Values are the Google Material Design 600-level shades which render well on both GitHub's light and dark mode backgrounds.

## Stroke width policy

Every edge width in the proposed palette is **~3× the current ~1.5px mermaid default** — the whole graph gets chunkier edges across the board, not just the "spine" class. Relative differentiation between classes is preserved on top of the uniform scale-up.

- **Class 1 FROM-parent + Class 4 external image**: **5px** (thick — "trust spine" edges; was 3.5px pre-rescaling)
- **Class 2 builder-stage FROM + Class 3 COPY-from**: **4px** (was 2.5px)
- **Class 5 L0.1 source**: **3px** with dotted dashArray (was 2px)

Rationale for the uniform 3× bump: at mermaid's default stroke width the 80+ edges in the current graph crowd together in the SVG; even with semantic shape/color variation the thin strokes don't survive GitHub's 1200px-wide render. 3–5px is the sweet spot where (a) edges remain legible at normal zoom on both mobile and desktop, (b) semantic class differentiation (5 vs 4 vs 3) is visible without being gratuitous, and (c) node :::class fills still dominate the visual (edges carry transit info; nodes carry identity).

All widths pinned in `linkStyle` lines so the SVG renders deterministically.

## Gherkin acceptance

```
Scenario: emitter produces ≥ 4 distinct edge classes
  Given FG-076 has shipped
  When I run `python3 scripts/image_from_graph.py --emit=mermaid`
  Then the output contains ≥ 1 line using `==>` syntax (Class 1/4)
   And the output contains ≥ 1 line using `-.->` syntax (Class 3)
   And the output contains ≥ 1 line using the dotted-5-char syntax for Class 5
   And every edge has a classification (no bare `-->` without a linkStyle pin)

Scenario: every edge has a linkStyle pin
  Given FG-076 has shipped
  When I count edges + linkStyle directives in the emitted mermaid
  Then the count of linkStyle directives ≥ the count of edges
   And every linkStyle index is < the count of edges

Scenario: legend is present in emitted output
  Given FG-076 has shipped
  When I read the first 40 lines of docs/image-dependency-graph.md
  Then the mermaid source carries a `subgraph Legend` block
   And it names every (shape, color) combo with its semantic

Scenario: tier colors match palette
  Given FG-076 has shipped
  When I grep the hex colors used in linkStyle
  Then exactly 7 distinct `stroke:#[0-9A-F]{6}` values appear
   And each corresponds to the documented tier-color mapping

Scenario: dep graph stays fresh after regen
  Given FG-076 has shipped
  When I run `make dep-graph && git diff --exit-code docs/image-dependency-graph.{md,svg}`
  Then git diff returns 0 (committed artifact matches regeneration)
```

## References

- Plan: `docs/plan/FG-076-dep-graph-edge-styling-plan.md`
- Red test: `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh`
- Current emitter: `scripts/image_from_graph.py`
- Visual target: `docs/image-dependency-graph.svg`
- Capabilities: `docs/CAPABILITIES.md#dep-graph.semantic-edge-styling`, extends `tooling.auto-dep-graph`
