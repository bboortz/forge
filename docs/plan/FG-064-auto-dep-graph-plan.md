---
id: FG-064
slug: auto-dep-graph
story: ../stories/FG-064-auto-dep-graph.md
---

# FG-064 plan — auto-generated image dependency graph

Story: [FG-064](../stories/FG-064-auto-dep-graph.md).

## Design delta

Two scripts share the work; one Makefile target drives them. The derived artifact (mermaid block inside `docs/image-dependency-graph.md`) is CI-gated for drift.

- **`scripts/verify-dockerfile-conformance.py`** (NEW) — the parser-contract lint. Every `images/*/Dockerfile` must follow the recognized `ARG *_REF=` convention, name every stage, and keep `COPY --from=<stage>` referencing a declared stage. Also enforces the no-intra-layer-edges invariant (scratch runtime cannot FROM another scratch runtime, etc.).
- **`scripts/image_from_graph.py`** (EXTEND) — gains `--emit=mermaid` + `--write <file>`. Reuses the existing FROM-graph parser; adds role classification, upstream-anchor detection, `COPY --from=` edge extraction, and strict 5-layer subgraph rendering.
- **`make dep-graph`** — invokes the emitter to rewrite `docs/image-dependency-graph.md` **between marker comments**. Narrative sections stay hand-written.
- **Pre-commit hook `dep-graph-fresh`** — runs `make dep-graph && git diff --exit-code docs/image-dependency-graph.md`. Fails any commit that leaves the file out of sync.
- **Pre-commit hook `verify-dockerfile-conformance`** — runs the lint on `images/*/Dockerfile` changes.
- **CI** — both hooks reach CI via `make test-fast` (both get new Makefile targets `verify-dockerfile-conformance` + `verify-dep-graph-fresh` + wired into the `test-fast` chain).

## Edit catalogue

### 1. `scripts/verify-dockerfile-conformance.py` (NEW)

Walks every `images/*/Dockerfile`, enforces:

1. Every `^ARG\s+\w+_REF=...` name is in the allowlist (one of `FORGE_BUILDER_REF`, `FORGE_BUILDER_GO_REF`, `FORGE_BUILDER_NODE_REF`, `SCRATCH_BASE_REF`, `DEBIAN_SLIM_REF`, `PYTHON_SLIM_REF`, `UBUNTU_SLIM_NOBLE_REF`, `NODE_SLIM_REF`, `HC_REF`).
2. Every `^ARG\s+\w+_REF=...` default value matches `ghcr.io/bboortz/<image>:<tag>` where `<image>` either exists under `images/` or is a known upstream helper (`hc`).
3. Every `^FROM` line matches one of:
   - `^FROM \${\w+_REF}(?: AS \w+)?$` (ARG-indirect, forge-signed base)
   - `^FROM scratch(?: AS \w+)?$` (literal scratch)
   - `^FROM <upstream>:<tag>(?: AS \w+)?$` where `<upstream>:<tag>` is on the dedicated-toolchain exemption list (`debian:trixie-slim`, `debian:sid-slim`, `python:3.14-slim-trixie`, `ubuntu:24.04`, `node:24-trixie-slim`, `golang:1.27-trixie`, `postgres:18`) — any other literal FROM is a lint failure (new upstream drift).
4. Every `COPY --from=<name>` references a stage declared by an earlier `^FROM ... AS <name>` in the same Dockerfile.
5. Every intermediate `FROM` (every `FROM` except the final / runtime stage AND every `FROM` that is the target of a later `COPY --from=`) carries an `AS <stage-name>` clause — no anonymous stages.
6. No intra-layer FROM edge: images in the same role tier (pre-builders / builders / scratch-runtimes / slim-runtimes) do not FROM each other. Tier assignment reuses the `_PRE_BUILDERS` / `_FORGE_BUILDERS` lists in `scripts/discover-images.sh`.

Exit codes: 0 = pass, 1 = any rule violated, 2 = IO / parser internal error.

### 2. `scripts/image_from_graph.py` (EXTEND)

Keep existing JSON `reverse` output as the default (`--emit=reverse-json`, default). New emitters:

- `--emit=mermaid` → emit the full mermaid block for `docs/image-dependency-graph.md` (between markers).
- `--write <file>` → in-place rewrite between `<!-- GENERATED:dep-graph START -->` and `<!-- GENERATED:dep-graph END -->` markers.

The mermaid emitter:

- Assigns each node to one of five layers via `_tier_of(name)`:
  - L0 upstream — any `FROM`/`ARG *_REF=` target that isn't a local image dir name (Docker Hub refs + `hc`, beaconry source).
  - L1 pre-builders — `name in _PRE_BUILDERS`.
  - L2 builders — `name in _FORGE_BUILDERS`.
  - L3 baseline — `name == "scratch-base-trixie"`.
  - L4 runtimes — everything else under `images/`. Within L4 the styling class is `:::slim` / `:::scratch` / `:::external` (external = `image.yaml` has `source:` block).
- Emits edges in deterministic order (alphabetical by source then target). FROM edges `-->`; `COPY --from=` edges `-.->`.
- Emits a verbatim `classDef` block matching the current hand-maintained palette.
- Emits a short in-markers legend above the `graph TD` so readers can decode solid/dashed + color classes without leaving the file.
- Nodes inside each subgraph are sorted alphabetically → predictable local diffs when adding an image.

Parsing additions:

- Literal `^FROM <upstream>:<tag>` lines contribute L0 nodes + L0 → L1 edges.
- `COPY --from=<stage>` lines, when `<stage>` resolves to an `ARG *_REF=` target, contribute a dashed edge.
- `image.yaml` with a top-level `source:` key marks the image as external — the FROM graph is fed by `image.yaml` `depends_on:` instead of Dockerfile parse (the Dockerfile isn't local).

### 3. `docs/image-dependency-graph.md` (EDIT)

Wrap the existing ` ```mermaid ... ``` ` fence in markers:

```
<!-- GENERATED:dep-graph START — regenerate with `make dep-graph` -->
```mermaid
...
```
<!-- GENERATED:dep-graph END -->
```

Narrative sections (Legend, Facts, chain-depth, Regenerating) stay outside the markers and are not touched by the generator.

Once implemented, `make dep-graph` is run once; its output replaces the current hand-written mermaid block. Any semantic equivalence (same node set + edge set) with the previous hand-written block is what we check — layout may reorder; styling palette is unchanged.

### 4. `Makefile` (EDIT)

```makefile
verify-dockerfile-conformance:
	@python3 scripts/verify-dockerfile-conformance.py

dep-graph:
	@python3 scripts/image_from_graph.py --emit=mermaid --write docs/image-dependency-graph.md

verify-dep-graph-fresh: dep-graph
	@git diff --exit-code docs/image-dependency-graph.md \
	  || { echo "✗ docs/image-dependency-graph.md is out of date — commit the regen"; exit 1; }
```

Add both to `test-fast`'s dependency list so CI picks them up for free:

```makefile
test-fast: lint verify-sid-pins verify-traceability verify-contracts verify-image-dirs verify-no-upstream-drift verify-dockerfile-conformance verify-dep-graph-fresh
```

### 5. `.pre-commit-config.yaml` (EDIT)

Two new local hooks under the `repo: local` section:

```yaml
      - id: verify-dockerfile-conformance
        name: verify-dockerfile-conformance (FG-064)
        language: system
        entry: python3 scripts/verify-dockerfile-conformance.py
        pass_filenames: false
        files: ^images/.*/Dockerfile$

      - id: dep-graph-fresh
        name: dep-graph-fresh (FG-064)
        language: system
        entry: bash -c 'make dep-graph && git diff --exit-code docs/image-dependency-graph.md'
        pass_filenames: false
        files: ^(images/.*/(Dockerfile|image\.yaml)|scripts/image_from_graph\.py|scripts/discover-images\.sh|docs/image-dependency-graph\.md)$
```

### 6. `.github/workflows/ci.yml` (no direct edit)

Both new gates reach CI via `make test-fast`. The `lint-verify` job already calls `make test-fast` (line 81 in current `ci.yml`), so the chain picks up the new targets automatically.

### 7. `tests/acceptance/test_FG_064_auto-dep-graph.sh` (NEW)

Encodes the 9 Gherkin scenarios (5 conformance + 4 graph). Sections: `[1]` lint allowlist present, `[2]` fleet passes conformance today, `[3]` emitter runs green + outputs mermaid, `[4]` emitter is idempotent, `[5]` markers preserved, `[6]` subgraph structure, `[7]` no-intra-layer-edges, `[8]` external-sourced via depends_on, `[9]` multi-builder visible.

### 8. `docs/CAPABILITIES.md` (EDIT)

Two new CAPs:

- `tooling.auto-dep-graph` — mermaid dep graph auto-generated from Dockerfile FROM-graph; drift-gated.
- `tooling.dockerfile-conformance` — every Dockerfile follows the recognized ARG / FROM / stage-naming conventions.

### 9. `docs/stories/INDEX.md` (EDIT)

Add FG-064 row.

## Alternatives rejected

- **Full Dockerfile templating** (yaml → Dockerfile.j2 → Dockerfile): breaks `docker build` for Beaconry + any downstream that clones + builds. Low ROI (template saves ~5-10 lines per Dockerfile; the body is per-image-specific). See story.
- **New `builder_depends_on:` field in `image.yaml`** (Option A): duplicates info already in the Dockerfile. Same drift risk unless lint-enforced — and if we're going to write the lint, derive-from-Dockerfile is strictly simpler.
- **PNG/SVG export of the graph**: GitHub renders mermaid inline, so an image file would duplicate the same information + decay separately.
- **More than 5 layers**: sub-splitting L4 into slim/scratch/external subgraphs makes the diagram busier without surfacing new structural information; the styling class already distinguishes them.

## Merge order

1. Branch from `dev`.
2. All edits in one commit.
3. `make dep-graph` runs clean locally; `make verify-dep-graph-fresh` + `make verify-dockerfile-conformance` both green.
4. Red test green locally.
5. PR → CI full-check → auto-merge.
6. No release / publish needed — pure tooling change.

## Rollout

- Zero image rebuilds. Zero consumer impact. Only `docs/image-dependency-graph.md` is rewritten.
- Future contributors: adding an image = add Dockerfile + image.yaml, run `make dep-graph`, commit.
- If a Dockerfile violates the conformance contract, the lint names which rule was broken + points at the Dockerfile line.

## Breaking changes

None for consumers. Internal: contributors now have to run `make dep-graph` before committing a Dockerfile change; the hook auto-regenerates as part of pre-commit so this is a one-line reminder, not a new workflow.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — conformance allowlist | Scenario 1 (ARG allowlist) | ⏳ |
| Gherkin — FROM convention | Scenario 2 | ⏳ |
| Gherkin — COPY --from= resolves | Scenario 3 | ⏳ |
| Gherkin — named stages | Scenario 4 | ⏳ |
| Gherkin — wired into pre-commit + CI | Scenario 5 | ⏳ |
| Gherkin — emitter well-formed | Scenario 6 | ⏳ |
| Gherkin — make dep-graph idempotent | Scenario 7 | ⏳ |
| Gherkin — markers respected | Scenario 8 | ⏳ |
| Gherkin — new image is caught | Scenario 9 | ⏳ |
| Gherkin — CI catches stale graph | Scenario 10 | ⏳ |
| Gherkin — external via depends_on | Scenario 11 | ⏳ |
| Gherkin — multi-builder | Scenario 12 | ⏳ |
| Gherkin — 5-layer subgraph structure | Scenario 13 | ⏳ |
| Gherkin — no intra-layer edges | Scenario 14 | ⏳ |
| Gherkin — alphabetical within subgraph | Scenario 15 | ⏳ |
| Gherkin — classDef + legend | Scenario 16 | ⏳ |
| Self-consistency | 2 new CAPs + bidirectional links | ⏳ |
| No consumer-contract break | zero image rebuilds, zero image changes | ✅ |
