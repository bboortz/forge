---
id: FG-064
slug: auto-dep-graph
status: ready
owner: bboortz
created: 2026-11-16
---

# FG-064 — Auto-generated image dependency graph

`docs/image-dependency-graph.md` is today a hand-maintained mermaid block. Every FG that adds a pre-builder (FG-042, FG-051, FG-058, FG-061), a builder (FG-046, FG-048), or an image routes through a manual refresh PR (last time: FG-115). The file drifted silently between FG-048 and FG-061 until noticed; that's the exact class of regression DD-TGD is built to prevent, and it's trivial to automate because `scripts/image_from_graph.py` (FG-059) already parses every Dockerfile's FROM-graph for smart-check fan-out.

FG-064 makes the mermaid block a **derived artifact**:
- Extend `scripts/image_from_graph.py` with an `--emit=mermaid` flag that renders the full graph (nodes classified by role, FROM edges solid, `COPY --from=` edges dashed).
- Output enforces a **strict 5-layer top-down structure** via mermaid `subgraph` clusters, matching the build-time publish-tier ordering (`.github/workflows/build.yml` 4-tier split + the upstream row that sits above tier 1).
- `make dep-graph` target regenerates `docs/image-dependency-graph.md` **between marker comments** — narrative sections (chain-depth story, dedicated-toolchain exemptions, trust-anchor consolidation table) remain hand-written outside the markers.
- Pre-commit hook + CI fast-check gate both run `make dep-graph && git diff --exit-code docs/image-dependency-graph.md`; drift is impossible to merge.
- GitHub renders the mermaid block natively, so readers always see the live-at-HEAD picture without running anything.

## Layered layout (mandatory)

The generator MUST emit a `graph TD` with exactly 5 vertically stacked `subgraph` clusters (top → bottom). Edges always flow downward between layers; no intra-layer edges except where structurally required (e.g., `forge-builder-python-trixie` → `scratch-base-trixie` within the builder → baseline hop — still top-down across layer boundaries).

| Layer | Subgraph id + title | Members (live at HEAD) | Style class |
|-------|---------------------|-------------------------|-------------|
| **0 — Upstream** | `L0_upstream` "Upstream (external to Forge)" | `python:3.14-slim-trixie`, `debian:trixie-slim`, `debian:sid-slim`, `ubuntu:24.04`, `node:24-trixie-slim`, `golang:1.27-trixie`, `postgres:18`, `anchore/syft:latest`, `ghcr.io/bboortz/hc:0.1.0` (upstream helper), `beaconry (source)` | `:::upstream` |
| **1 — Pre-builders** | `L1_prebuilders` "Forge pre-builders (publish-pre-builders tier)" | `debian-slim-sid`, `debian-slim-trixie`, `node-slim-trixie`, `python-slim-trixie`, `ubuntu-slim-noble` | `:::prebuilder` |
| **2 — Builders** | `L2_builders` "Forge builders (publish-builders tier — never runtime)" | `forge-builder-go-trixie`, `forge-builder-node-trixie`, `forge-builder-python-trixie` | `:::builder` |
| **3 — Baseline** | `L3_baseline` "Forge baseline (publish-base tier — scratch overlay)" | `scratch-base-trixie` | `:::baseline` |
| **4 — Runtimes** | `L4_runtimes` "Runtimes (publish-base + publish-derivatives tiers)" | slim: `cadvisor-slim-trixie`, `github-runner-noble`, `healthy-scratch-trixie` (slim-shape runtime), `ipmi-exporter-slim-trixie`, `postgres-slim-trixie`, `uptime-kuma-slim-trixie` • scratch: `alertmanager-scratch-trixie`, `ipmi-exporter-scratch-trixie`, `mosquitto-scratch-trixie`, `nginx-scratch-trixie`, `node-exporter-scratch-trixie`, `postgres-scratch-trixie`, `prometheus-scratch-trixie`, `python-scratch-trixie`, `redis-scratch-trixie` • external: `beaconry-hub`, `beaconry-scout`, `beaconry-telegram-mock` | `:::slim` / `:::scratch` / `:::external` |

Rules the emitter applies:

1. **Membership is derived, not configured**. Layer assignment uses `scripts/discover-images.sh` tier membership (`pre-builders`, `builders`, `base`, `derivatives`) + `image.yaml source:` → external-sourced (within layer 4). Upstream nodes are discovered from literal `^FROM <upstream>` lines + `ARG *_REF=` defaults pointing at a ref NOT present as an image dir.
2. **Node ordering within a subgraph is alphabetical**, so adding a new image produces a predictable local diff.
3. **Edge directionality**: all edges run downward. Solid `-->` for FROM; dashed `-.->` for `COPY --from=` overlays (hc embed + scratch-base overlay).
4. **Intra-layer edges are forbidden** except at the layer boundary itself (e.g., `L2 → L3` where `forge-builder-python-trixie --> scratch-base-trixie`). The emitter fails the Dockerfile-conformance lint if a Dockerfile produces an intra-layer edge (i.e., a scratch runtime trying to FROM another scratch runtime).
5. **Styling is deterministic** — `classDef` block is emitted verbatim at the end, matching the current hand-maintained palette.
6. **Legend is emitted** above the diagram inside the markers so readers understand solid-vs-dashed + the 5 color classes without leaving the file.

## 9 canonical answers

1. **Who** — Forge maintainer (adding or renaming an image); external reader on GitHub (wants the current shape of the fleet); Beaconry / auditor (wants a trusted, machine-verifiable artifact of the supply-chain graph).

2. **When** — Fires on every Dockerfile / image.yaml edit: pre-commit regens + diffs; CI fast-check tier regens + diffs; GitHub renders on every file view.

3. **What success looks like**:
   - `scripts/image_from_graph.py --emit=mermaid` outputs a well-formed mermaid block with role-classified nodes (upstream, pre-builder, builder, baseline, slim, scratch, external) + FROM edges + COPY-from edges (hc, scratch-base).
   - `make dep-graph` edits `docs/image-dependency-graph.md` in place, strictly between `<!-- GENERATED:dep-graph START -->` and `<!-- GENERATED:dep-graph END -->` markers.
   - Pre-commit hook `dep-graph-fresh` fails any commit that leaves the file out of sync.
   - CI fast-check job (part of the Lint & verify tier) runs the same gate on PRs.
   - Narrative prose outside the markers (chain-depth table, dedicated-toolchain exemptions, trust-anchor consolidation facts, regenerating recipe) is preserved verbatim across regenerations.
   - Current manual mermaid becomes the generator's first output — regenerating should produce a semantically-equivalent diagram (node set + edge set identical; layout may reorder, that's fine).

4. **Urgency** — Infrastructure quality-of-life. Stops the "docs went stale since FG-X" class entirely. Not security-critical.

5. **Happy path**:
   1. Branch `feat/FG-064-auto-dep-graph` from dev.
   2. **Add a Dockerfile-conformance lint** `scripts/verify-dockerfile-conformance.py`. Gates: every `images/*/Dockerfile` MUST
      - Use ONLY recognized `ARG <X>_REF=` conventions for forge-signed base references: `ARG <NAME>_REF=ghcr.io/bboortz/<repo>:<tag>` (allowlist loaded from `scripts/image_from_graph.py`'s known-ref table). Anything else is a lint failure with "unknown ARG ref convention — extend _KNOWN_REF_PATTERNS first".
      - Have every `FROM` line either match `^FROM ${<NAME>_REF}(?: AS \w+)?$` (ARG-indirect) OR `^FROM <upstream>:<tag>(?: AS \w+)?$` (literal, pre-builders + dedicated-toolchain exemptions only). No inline tags on forge-signed refs.
      - Have every `COPY --from=<name>` reference a stage declared by `FROM ... AS <name>` earlier in the same Dockerfile.
      - Multi-stage builds declare each stage with `AS <stage-name>` (no anonymous intermediate stages).
   3. Extend `scripts/image_from_graph.py` with `--emit=mermaid`. New responsibilities:
      - Role classification via existing `scripts/discover-images.sh` tier membership (pre-builders, builders, base, derivatives) + `image.yaml source:` → external.
      - Extra edge types: `COPY --from=<ref>` (for hc + scratch-base overlays).
      - Upstream Docker Hub anchors inferred from literal `^FROM <upstream>` lines.
   4. Wrap current mermaid block in `<!-- GENERATED:dep-graph START -->` / `<!-- END -->` markers.
   5. Add `make dep-graph` target: `python3 scripts/image_from_graph.py --emit=mermaid --write docs/image-dependency-graph.md`.
   6. Add `.pre-commit-config.yaml` entries: `verify-dockerfile-conformance` + `dep-graph-fresh` (local hooks; scope to `images/*/Dockerfile`, `images/*/image.yaml`, `scripts/image_from_graph.py`, `docs/image-dependency-graph.md`).
   7. Add `.github/workflows/ci.yml` steps in the Lint & verify tier: both of the above.
   8. Red acceptance test `tests/acceptance/test_FG_064_auto-dep-graph.sh`.
   9. Run `make dep-graph` once; commit the (hopefully identical) regenerated output.

6. **Edge cases / failure modes**:
   - **ARG indirection vs. literal FROM**: generator must handle both `FROM ${FORGE_BUILDER_NODE_REF}` (resolved via ARG default) AND `FROM node:24-trixie-slim` (literal). FG-059's existing parser handles the ARG case; literal FROMs are easy.
   - **Multi-builder images**: prometheus-scratch + alertmanager-scratch (Node UI + Go builder); ipmi-exporter-scratch (Python C-builder + Go builder). Generator must emit multiple FROM edges with distinct source stages.
   - **External-sourced (FG-012)**: beaconry-hub/scout/mock pull their Dockerfiles from `github.com/bboortz/beaconry` at build time — no local Dockerfile to parse. Fall back to `image.yaml` `depends_on` for the FROM parent, emit a purple-styled node with a dashed arrow from a synthetic `BEACONRY_SRC` node.
   - **`COPY --from=<name>` with ARG indirection** (`COPY --from=hc /hc /hc` where the stage name `hc` comes from `FROM ${HC_REF} AS hc`): generator must trace stage aliases back to their FROM ref.
   - **Narrative-section coupling**: if a hand-written paragraph outside the markers refers to "5 pre-builders" by count, that count isn't auto-synced. Mitigation: only the diagram inside markers is canonical; narrative references are advisory. Acceptance test does NOT assert numbers in the narrative.
   - **Unknown ARG convention**: if a future Dockerfile introduces a new ARG like `ARG REDIS_SLIM_REF=ghcr.io/bboortz/redis-slim:latest` that the parser's allowlist doesn't match, the edge is silently dropped. Mitigation: `image_from_graph.py` already has a growing `_KNOWN_REF_PATTERNS` or similar; FG-064 should add a self-test asserting every `ARG *_REF=ghcr.io/bboortz/` occurrence in `images/*/Dockerfile` resolves to an edge in the generated graph — fail if any slip through.

7. **Out of scope**:
   - Changing `image.yaml` schema (no new `builder_depends_on:` field — Option A from the earlier design discussion is deferred).
   - Generating any Dockerfile content from image.yaml (templating — ruled out as low-ROI).
   - PNG / SVG export (mermaid in markdown is sufficient; GitHub renders inline).
   - Auto-updating narrative sections (chain-depth story, dedicated-toolchain exemptions, trust-anchor consolidation table).
   - Chain-depth invariant checking in the generator itself — can be a follow-up once the extractor exists.
   - More than 5 layers (e.g., sub-splitting layer 4 into "slim" + "scratch" + "external" subgraphs). The 5-layer model matches the 4-tier publish ordering + the upstream row; further splits make the diagram busier without new information.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `tooling.auto-dep-graph` — mermaid dependency graph auto-generated from live Dockerfile FROM-graph + image.yaml roles; drift-gated by CI + pre-commit hook.
   - NEW `tooling.dockerfile-conformance` — every `images/*/Dockerfile` follows a strict, parser-friendly format (allowlisted `ARG *_REF=` convention, named stages, resolvable `COPY --from=` references, no inline tags on forge-signed refs). Gated by `scripts/verify-dockerfile-conformance.py` at pre-commit + CI.

## Gherkin acceptance

```
Scenario: every Dockerfile uses a recognized ARG *_REF convention
  Given every file under images/*/Dockerfile
  When scripts/verify-dockerfile-conformance.py runs
  Then every ARG line whose name ends in _REF matches the allowlist
      (FORGE_BUILDER_REF, FORGE_BUILDER_GO_REF, FORGE_BUILDER_NODE_REF,
       SCRATCH_BASE_REF, DEBIAN_SLIM_REF, PYTHON_SLIM_REF,
       UBUNTU_SLIM_NOBLE_REF, NODE_SLIM_REF, HC_REF)
  And every such ARG default resolves to ghcr.io/bboortz/<repo>:<tag>
  And unknown ref-ARG names fail the lint with an actionable error

Scenario: every FROM is either literal or ARG-indirect per convention
  Given every file under images/*/Dockerfile
  When scripts/verify-dockerfile-conformance.py runs
  Then every ^FROM line matches one of:
      FROM ${<ARG_FROM_ALLOWLIST>}( AS <stage>)?
      FROM <upstream>:<tag>( AS <stage>)?   # pre-builders + dedicated-toolchain
      FROM scratch( AS <stage>)?

Scenario: every COPY --from=<name> resolves to a declared stage
  Given every file under images/*/Dockerfile
  When scripts/verify-dockerfile-conformance.py runs
  Then every COPY --from=<name> reference finds a matching
      ^FROM ... AS <name> earlier in the same file

Scenario: every multi-stage build names every stage
  Given every file under images/*/Dockerfile
  When scripts/verify-dockerfile-conformance.py runs
  Then every ^FROM ... (not the last / runtime stage, or any that is the target
      of a COPY --from=) carries an AS <stage-name> clause

Scenario: conformance lint is wired into pre-commit + CI
  Given the full repo state
  Then .pre-commit-config.yaml contains an id: verify-dockerfile-conformance
  And .github/workflows/ci.yml's Lint & verify job runs the same check

Scenario: emitter produces a valid mermaid block for the current fleet
  Given current HEAD state
  When scripts/image_from_graph.py --emit=mermaid runs
  Then stdout contains "```mermaid" and "```" fence markers
  And every image dir under images/ appears as at least one node id
  And every forge-signed base reference in images/*/Dockerfile (ARG or literal FROM)
      appears as at least one edge in the output

Scenario: make dep-graph updates the file idempotently
  Given no Dockerfile or image.yaml changes since last regeneration
  When make dep-graph runs twice in a row
  Then docs/image-dependency-graph.md is byte-identical before and after both runs

Scenario: make dep-graph respects the GENERATED markers
  Given docs/image-dependency-graph.md has narrative prose both before the
    <!-- GENERATED:dep-graph START --> marker and after the <!-- END --> marker
  When make dep-graph regenerates
  Then the prose outside the markers is unchanged
  And only the mermaid block between the markers is rewritten

Scenario: adding a new image makes the graph stale and the hook catches it
  Given a new images/foo-scratch-trixie/Dockerfile FROMing scratch-base-trixie
  When git commit runs without having re-run make dep-graph
  Then the pre-commit dep-graph-fresh hook fails with
      "docs/image-dependency-graph.md is out of date — run `make dep-graph`"

Scenario: CI full-check fails on committed-but-stale graph
  Given a PR that touches images/*/Dockerfile but not docs/image-dependency-graph.md
  When CI's Lint & verify tier runs
  Then the dep-graph-fresh step fails with the same "out of date" message

Scenario: external-sourced images resolve via image.yaml depends_on
  Given beaconry-hub/image.yaml declares depends_on: [python-scratch-trixie]
  And beaconry-hub has no local Dockerfile (FG-012 — pulled at build time)
  When make dep-graph regenerates
  Then the mermaid block contains an edge python-scratch-trixie --> beaconry-hub

Scenario: multi-builder images show every builder edge
  Given images/prometheus-scratch-trixie/Dockerfile declares
      FROM ${FORGE_BUILDER_GO_REF} AS builder AND
      FROM ${FORGE_BUILDER_NODE_REF} AS ui-builder
  When make dep-graph regenerates
  Then the mermaid block contains BOTH:
      forge-builder-go-trixie --> prometheus-scratch-trixie
      forge-builder-node-trixie --> prometheus-scratch-trixie

Scenario: output enforces the 5-layer subgraph structure
  Given current HEAD state
  When scripts/image_from_graph.py --emit=mermaid runs
  Then the output contains exactly 5 subgraph blocks with ids
      L0_upstream, L1_prebuilders, L2_builders, L3_baseline, L4_runtimes
  And subgraphs appear in that order top-down
  And every image dir under images/ sits inside exactly one subgraph
  And subgraph membership matches scripts/discover-images.sh tier output
      (pre-builders → L1, builders → L2, scratch-base-trixie → L3, rest → L4)

Scenario: no intra-layer edges allowed
  Given every file under images/*/Dockerfile
  When scripts/verify-dockerfile-conformance.py runs
  Then no image in layer N FROMs another image in layer N
      (e.g., no scratch runtime FROMs another scratch runtime;
       no pre-builder FROMs another pre-builder)

Scenario: nodes inside each subgraph are alphabetical
  Given the regenerated mermaid block
  When reading each subgraph in order
  Then nodes within each subgraph appear in alphabetical order by image dir name
  And adding a new image affects only the subgraph it joins
      (predictable local diff; no fleet-wide re-ordering)

Scenario: classDef + legend are emitted verbatim
  Given the regenerated mermaid block
  Then the final classDef block matches the hand-maintained palette exactly
      (upstream, prebuilder, builder, baseline, slim, scratch, external)
  And a legend block above the diagram (inside the markers) names
      solid arrow, dashed arrow, and each of the 7 color classes
```

## References

- Plan: `docs/plan/FG-064-auto-dep-graph-plan.md` (follow-up)
- Red test: `tests/acceptance/test_FG_064_auto-dep-graph.sh` (follow-up)
- Existing parser we're extending: `scripts/image_from_graph.py` (FG-059)
- Current hand-written target to regenerate: `docs/image-dependency-graph.md` (last manual refresh: PR #115 for FG-048/051/058/061)
- Capabilities: see `docs/CAPABILITIES.md` after `tooling.auto-dep-graph` lands.
