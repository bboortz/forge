---
id: FG-065
slug: forge-builder-dogfood-symmetry
status: ready
owner: bboortz
created: 2026-11-17
---

# FG-065 — Every programming language gets both a pre-builder AND a builder (Python / Go / Node symmetry)

Establish and enforce a new architectural rule: **every programming language family in the Forge fleet has both (a) a forge-rooted slim runtime pre-builder and (b) a forge-rooted toolchain builder**. Today Python satisfies this; Node partially (pre-builder exists, builder doesn't dogfood it); Go doesn't (no pre-builder at all, builder FROMs upstream directly as a "dedicated-toolchain exemption").

| Language | Pre-builder (own image) | Builder image | Dogfooded? |
|----------|------------------------|---------------|------------|
| Python | `python-slim-trixie` | `forge-builder-python-trixie` | ✅ FG-042 |
| Node | `node-slim-trixie` (FG-061) | `forge-builder-node-trixie` (FG-048) | ⚠️ builder still FROMs `node:24-trixie-slim` upstream |
| Go | *(none)* | `forge-builder-go-trixie` (FG-046) | ⚠️ builder FROMs `golang:1.27-trixie` upstream directly |

FG-065 fills both gaps in one PR:

1. **Node**: flip `forge-builder-node-trixie` to `FROM ${NODE_SLIM_REF}` (dogfood). Collapses `node:24-trixie-slim` from 2 forge consumers to 1 (`node-slim-trixie` only).
2. **Go**: introduce `go-slim-trixie` as the new 6th pre-builder (FROM `golang:1.27-trixie` + apt-upgrade + ca-certs + dumb-init, same shape as `node-slim-trixie`), and flip `forge-builder-go-trixie` to `FROM ${GO_SLIM_REF}` (dogfood). Closes the only remaining language gap.

After FG-065, zero upstream Docker Hub bases are consumed directly by a Forge builder, AND every language family we support has both image types. The "dedicated-toolchain exemption" callout is retired entirely; the new architectural rule becomes the invariant for every future language family (Rust, Zig, Ruby, Java, etc. — each would land as a sibling pair `<lang>-slim-trixie` + `forge-builder-<lang>-trixie`).

## Architectural principle (becomes memory/design-decisions.md § "Language family image pairs")

> Every programming language family in the Forge fleet ships two co-published images:
>
> - **`<lang>-slim-trixie`** — forge-rooted slim runtime pre-builder. FROMs the canonical upstream for that language (e.g. `golang:1.27-trixie`, `node:24-trixie-slim`, `python:3.14-slim-trixie`) + apt-upgrade + ca-certificates + dumb-init. Sits in the `publish-pre-builders` CI tier. Consumed by (a) downstream slim runtimes that need the language's runtime surface, and (b) the corresponding toolchain builder (dogfood).
> - **`forge-builder-<lang>-trixie`** — forge-rooted toolchain builder. FROMs the `<lang>-slim-trixie` pre-builder (never upstream directly) + installs the language toolchain surface needed to build from source (git, curl, jq, make/g++, syft, corepack for Node, etc.). Sits in the `publish-builders` CI tier. Consumed only at builder-stage by scratch / slim derivatives.
>
> The pair is co-published daily. A single upstream version bump propagates atomically through both images and then to every downstream consumer. The "dedicated-toolchain exemption" (Go/Node builders FROMing upstream directly) is RETIRED by FG-065 — no new exemptions are granted.

## 9 canonical answers

1. **Who** — Forge maintainer auditing supply-chain structure (wants dogfood symmetry across all three builder lineages). FG-042 invariant reviewer (wants exactly-one forge consumer per upstream anchor, no carve-outs). Daily-cron operator (upstream Go/Node bumps now land atomically: upstream → <X>-slim-trixie → forge-builder-X-trixie → every X-derivative, instead of two parallel pulls of the same upstream).

2. **When** — Fires on every daily cron. `publish-pre-builders` (now 6 pre-builders) must land before `publish-builders` (now all three builders depend on a pre-builder). Already encoded in the 4-tier split — only membership grows.

3. **What success looks like**:
   - `images/go-slim-trixie/` exists with the same shape as `node-slim-trixie` (FROM `golang:1.27-trixie` + apt-upgrade + ca-certs + dumb-init + OCI labels; standard pre-builder PROMISES).
   - `images/forge-builder-node-trixie/Dockerfile`: `ARG NODE_BASE` → `ARG NODE_SLIM_REF` + `FROM ${NODE_SLIM_REF}`.
   - `images/forge-builder-go-trixie/Dockerfile`: `ARG GO_BASE` → `ARG GO_SLIM_REF` + `FROM ${GO_SLIM_REF}`.
   - `images/forge-builder-{node,go}-trixie/image.yaml` grow `depends_on: [<slim-trixie>]`.
   - `scripts/discover-images.sh` `_PRE_BUILDERS` grows from 5 to **6**.
   - `scripts/verify-no-upstream-drift.sh` adds `'golang:1.27-trixie'` to `_UPSTREAM_ANCHORS` + bumps `_EXPECTED` 5 → **6** (the one Dockerfile FROMing `golang:1.27-trixie` literally is the new `go-slim-trixie` pre-builder; FBG's indirect FROM doesn't match the grep).
   - `scripts/verify-dockerfile-conformance.py` _KNOWN_REF_ARGS gains `GO_SLIM_REF`; _PRE_BUILDERS gains `go-slim-trixie`.
   - `scripts/build-image.sh` gains auto-build + ref-resolution + `--build-arg GO_SLIM_REF` wiring (mirror of FG-061's NODE_SLIM_REF integration).
   - `.github/workflows/build.yml` `publish-pre-builders` tier comment lists 6 pre-builders.
   - `memory/design-decisions.md` + `memory/docker-standard.md`: "dedicated-toolchain exemption" callout retired; replaced with "every upstream passes through a forge pre-builder."
   - FG-064's auto-regenerated dep graph shows `golang:1.27-trixie → go-slim-trixie → forge-builder-go-trixie` AND `node-slim-trixie → forge-builder-node-trixie` as solid FROM edges; the direct upstream-to-FBG and upstream-to-FBN edges are GONE.
   - All existing acceptance + smoke tests still pass (uptime-kuma, prometheus-scratch, alertmanager-scratch, cadvisor-slim, node-exporter-scratch, ipmi-exporter-{slim,scratch}, postgres-slim).
   - `scratch-base-trixie` size + python-scratch-trixie size + node-exporter-scratch-trixie size all stay within 10% of their pre-FG-065 values (apt-upgrade on an already-current base is idempotent).

4. **Urgency** — Infrastructure quality-of-life + structural cleanup. Not security-material. One-day scope but touches many files (6 pre-builder count propagates through scripts + docs + CI comment + tests).

5. **Happy path**:
   1. Branch `feat/FG-065-forge-builder-dogfood-symmetry` from `dev`.
   2. Create `images/go-slim-trixie/` — Dockerfile + image.yaml (`tag: latest`, `platforms: [linux/amd64]`, no `depends_on`) + PROMISES.yaml (8 promises mirroring node-slim-trixie: `runtime.go-toolchain`, `files.ca-certificates`, `files.dumb-init`, `apt.freshly-upgraded`, `apt.no-cache`, `presence.shell`, `shape.size-budget`, `scan.nonzero-accepted`) + scan-baseline.json + sid-pins/.gitkeep + 7 smokes (`smoke_go_version.sh`, `smoke_ca_bundle.sh`, `smoke_dumb_init.sh`, `smoke_apt_upgraded.sh`, `smoke_no_apt_cache.sh`, `smoke_has_shell.sh`, `smoke_size.sh`).
   3. Edit `images/forge-builder-go-trixie/Dockerfile` (ARG + FROM swap).
   4. Edit `images/forge-builder-node-trixie/Dockerfile` (ARG + FROM swap).
   5. Edit both `image.yaml` files to add `depends_on`.
   6. Update `scripts/verify-no-upstream-drift.sh` (add `golang:1.27-trixie` + `_EXPECTED` 5 → 6).
   7. Update `scripts/discover-images.sh` `_PRE_BUILDERS` array.
   8. Update `scripts/verify-dockerfile-conformance.py` (`_KNOWN_REF_ARGS` + `_PRE_BUILDERS`).
   9. Update `scripts/build-image.sh` — GO_SLIM_REF auto-build-dependency + ref-resolution + forge-local fallback + `_HAS_LOCAL_DEP` check + `--build-arg GO_SLIM_REF`.
   10. Update `.github/workflows/build.yml` publish-pre-builders comment.
   11. Update `docs/CAPABILITIES.md`:
       - NEW `build.go-slim-base` (mirror of FG-061's `build.node-slim-base`).
       - EXT `build.pre-builder-tier` (6 members now; FG-065 mentioned alongside FG-061).
       - EXT `image.forge-rooted-slim-bases` (add Go family; `_EXPECTED=6`).
       - EXT `build.shared-node-builder` + `build.shared-go-builder` (now dogfood their respective pre-builders).
   12. Update `docs/stories/INDEX.md` — FG-065 row.
   13. Update `memory/design-decisions.md` — retire dedicated-toolchain exemption callout.
   14. Update `memory/docker-standard.md` — update chain-depth example (Go now lands at 5 hops, same as Python).
   15. Red acceptance test `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh` (8 sections).
   16. Update FG-042 + FG-061 inline assertions that check pre-builder count (now 6).
   17. Update FG-048a (shared-node-builder) + FG-046a (shared-go-builder) acceptance tests if they assert FROM targets.
   18. `make dep-graph` → regen asserts the new edges + `go-slim-trixie` node.
   19. Local full-build sweep: `go-slim-trixie` + `node-slim-trixie` (unchanged) + `forge-builder-{go,node}-trixie` (new FROMs) + every downstream consumer. All smokes green.
   20. `make check` passes; chain depth confirmed ≤ 5.
   21. PR → CI full-check → auto-merge → release → next cron re-publishes.

6. **Edge cases / failure modes**:
   - **Chain depth**: deepest Python chain is 5 hops (unchanged). New deepest Go chain: `debian:trixie-slim` (via `golang:1.27-trixie`) → `golang:1.27-trixie` → `go-slim-trixie` → `forge-builder-go-trixie` → `scratch-base-trixie` → scratch runtime (e.g. node-exporter-scratch-trixie) = **5 hops, at the cap**. Node derivative chain: 4 hops (same as today's deepest Node chain). FG-065 brings Go to parity with Python. No chain exceeds 5.
   - **Build caching**: `forge-builder-{go,node}-trixie`'s apt layer rehashes because FROM changed. One-time cache miss; afterward the shared `<X>-slim-trixie` layer is cached + inherited.
   - **Daily cron ordering**: `publish-pre-builders` must complete before `publish-builders`. Already enforced by the 4-tier `needs:` chain; FG-065 just grows the pre-builders matrix from 5 to 6.
   - **Dev-loop local build**: `scripts/build-image.sh` already handles auto-build dependencies for PYTHON_SLIM_REF, NODE_SLIM_REF, UBUNTU_SLIM_NOBLE_REF. FG-065 adds a parallel GO_SLIM_REF block.
   - **go-slim-trixie size**: `golang:1.27-trixie` is ~800 MB (Go toolchain is big). apt-upgrade + ca-certs + dumb-init adds a few MB. `smoke_size.sh` budget allows ≤ upstream × 1.1 (same ratio as node-slim-trixie).
   - **go-slim-trixie has only one consumer today (FBG)**: structurally justified by closing the exemption. If a future Go-runtime image appears (unlikely — Go produces static binaries, no runtime Go needed), it can FROM go-slim-trixie directly.
   - **`forge-builder-go-trixie`'s current `ARG GO_BASE` default is `golang:1.27-trixie`**. Changing to `ARG GO_SLIM_REF=ghcr.io/bboortz/go-slim-trixie:latest` changes the upstream path. Downstream Go-source images (cadvisor, node-exporter, prometheus, alertmanager, ipmi-exporter-{slim,scratch}, postgres-slim-gosu-builder) all use `${FORGE_BUILDER_GO_REF}` for their builder stage — no direct downstream edit needed.
   - **memory/docker-standard.md's chain-depth example** currently says "Current deepest trust chain ... = 5 hops to a scratch runtime like python-scratch-trixie". After FG-065, Go matches. Update the memory to reflect "python-scratch OR node-exporter-scratch OR any other Go/Node scratch derivative" = 5 hops. The cap of 5 stays unchanged.

7. **Out of scope**:
   - **Changing anything about the Python dogfood** (FG-042 already landed; FBT already FROMs python-slim-trixie).
   - **Changing anything about the Dockerfile body** of either forge-builder (apt-install lists, syft version, corepack enable, etc.) — pure FROM swap for both.
   - **Consumer edits**: uptime-kuma, prometheus-scratch, alertmanager-scratch, cadvisor, etc. all use `${FORGE_BUILDER_<X>_REF}` — unchanged.
   - **Adding `-slim-trixie` pre-builders for any other upstream** (`postgres:18`, `ubuntu:24.04` already has `ubuntu-slim-noble`). This FG closes only the Go + Node gaps.
   - **Changing cosign identity / verification URL** — no public-contract change.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `arch.language-family-image-pair` — architectural invariant: every programming language family in the Forge fleet ships two co-published images (`<lang>-slim-trixie` + `forge-builder-<lang>-trixie`). The builder always dogfoods the pre-builder. Retires the "dedicated-toolchain exemption" callout; the invariant replaces it. New language families (Rust, Zig, Ruby, Java, …) land as sibling pairs by convention.
   - NEW `build.go-slim-base` — Forge-rooted Go 1.27 toolchain slim pre-builder. FROMs `golang:1.27-trixie` + apt-upgrade + ca-certificates + dumb-init. Sits in `publish-pre-builders` tier. Consumed by `forge-builder-go-trixie` (dogfood).
   - EXT `build.pre-builder-tier` — 6 members now (debian-slim-sid, debian-slim-trixie, go-slim-trixie, node-slim-trixie, python-slim-trixie, ubuntu-slim-noble).
   - EXT `image.forge-rooted-slim-bases` — Go family added; `_EXPECTED=6`; exemption callout retired; `arch.language-family-image-pair` rule becomes the invariant.
   - EXT `build.shared-node-builder` — now dogfoods `node-slim-trixie` (invariant satisfied).
   - EXT `build.shared-go-builder` — now dogfoods `go-slim-trixie` (invariant satisfied).

## Gherkin acceptance

```
Scenario: images/go-slim-trixie/ exists with the standard pre-builder shape
  Given current HEAD
  Then images/go-slim-trixie/Dockerfile, image.yaml, PROMISES.yaml,
       scan-baseline.json, sid-pins/, and tests/smoke_*.sh (7 smokes) all exist

Scenario: go-slim-trixie Dockerfile FROMs the upstream Go base
  Given images/go-slim-trixie/Dockerfile at HEAD
  Then it contains `^FROM golang:1.27-trixie`
  And it apt-upgrades + installs ca-certificates + dumb-init

Scenario: forge-builder-go-trixie dogfoods go-slim-trixie
  Given images/forge-builder-go-trixie/Dockerfile at HEAD
  Then the top-level FROM references ${GO_SLIM_REF}
      (default ghcr.io/bboortz/go-slim-trixie:latest)
  And it does NOT reference golang:1.27-trixie directly or via ${GO_BASE}

Scenario: forge-builder-node-trixie dogfoods node-slim-trixie
  Given images/forge-builder-node-trixie/Dockerfile at HEAD
  Then the top-level FROM references ${NODE_SLIM_REF}
      (default ghcr.io/bboortz/node-slim-trixie:latest)
  And it does NOT reference node:24-trixie-slim directly or via ${NODE_BASE}

Scenario: image.yaml depends_on grows for both builders
  Given images/forge-builder-go-trixie/image.yaml at HEAD
  Then depends_on includes 'go-slim-trixie'
  Given images/forge-builder-node-trixie/image.yaml at HEAD
  Then depends_on includes 'node-slim-trixie'

Scenario: pre-builder count grows 5 → 6
  Given scripts/discover-images.sh pre-builders
  When it runs
  Then the matrix has 6 entries alphabetical:
      [debian-slim-sid, debian-slim-trixie, go-slim-trixie,
       node-slim-trixie, python-slim-trixie, ubuntu-slim-noble]

Scenario: verify-no-upstream-drift accounts for golang:1.27-trixie
  Given scripts/verify-no-upstream-drift.sh
  Then _UPSTREAM_ANCHORS includes 'golang:1.27-trixie'
  And _EXPECTED is 6 (one literal `^FROM golang:1.27-trixie` in go-slim-trixie/Dockerfile)
  And the guard exits 0

Scenario: chain depth stays ≤ 5 hops for every scratch runtime
  Given the FG-064 auto-regenerated dep graph
  When chain depth is computed from upstream to the deepest scratch runtime
  Then no path exceeds 5 hops
  And the new deepest Go chain (debian → golang → go-slim → forge-builder-go → scratch-base → scratch runtime) is exactly 5

Scenario: downstream consumers all still build + smoke green
  Given forge-local/forge-builder-go-trixie:latest + forge-local/forge-builder-node-trixie:latest both built from the new FROMs
  When every downstream (uptime-kuma, prometheus-scratch, alertmanager-scratch,
       cadvisor-slim, node-exporter-scratch, ipmi-exporter-{slim,scratch},
       postgres-slim) is rebuilt
  Then every image builds successfully
  And every smoke suite exits 0

Scenario: dep graph shows the new edges after `make dep-graph`
  Given docs/image-dependency-graph.md regenerated
  Then the mermaid block contains:
      `golang:1.27-trixie --> go-slim-trixie` (solid, upstream → L1)
      `go-slim-trixie --> forge-builder-go-trixie` (solid, L1 → L2)
      `node-slim-trixie --> forge-builder-node-trixie` (solid, L1 → L2)
  And it does NOT contain:
      any upstream → forge-builder-go-trixie direct edge
      any upstream → forge-builder-node-trixie direct edge
  And the SVG is regenerated accordingly

Scenario: memory + design-decisions updated
  Given memory/design-decisions.md and memory/docker-standard.md
  Then the "dedicated-toolchain exemption" callout is removed (no exempt families remain)
  And the chain-depth example notes that Python AND Go both land at 5 hops

Scenario: language-family-image-pair invariant documented
  Given memory/design-decisions.md at HEAD
  Then a new section "Language family image pairs" exists
  And it states that every language family ships both <lang>-slim-trixie
      AND forge-builder-<lang>-trixie, with the builder dogfooding the pre-builder
  And it lists Python, Go, Node as the current satisfying families
  And it names Rust / Zig / Ruby / Java as the pattern for future families

Scenario: conformance lint catches an unpaired language family
  Given a hypothetical future commit that adds images/forge-builder-rust-trixie/
       but NOT a matching images/rust-slim-trixie/
  When scripts/verify-dockerfile-conformance.py runs (extended per FG-065)
  Then the lint rejects the commit with
      "forge-builder-rust-trixie: missing sibling pre-builder rust-slim-trixie
       (FG-065 arch.language-family-image-pair invariant)"
```

## References

- Plan: `docs/plan/FG-065-forge-builder-dogfood-symmetry-plan.md` (follow-up)
- Red test: `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh` (follow-up)
- Predecessor pattern: FG-042 (python dogfood), FG-061 (node-slim-trixie pre-builder + uptime-kuma migration).
- Capabilities touched: `build.shared-node-builder` (FG-048), `build.shared-go-builder` (FG-046), `image.forge-rooted-slim-bases`, `build.pre-builder-tier`.
- This FG reuses the FG-061 playbook almost verbatim (new pre-builder image + 5-script tooling update + `_EXPECTED` bump + dep-graph auto-regen + memory update). Scope is Node-side (half of FG-061) + Go-side (full FG-061 analog).
