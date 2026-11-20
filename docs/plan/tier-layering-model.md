---
title: Tier layering model + migration plan
spans: FG-067, FG-068, FG-069, FG-070, FG-071
status: proposed
created: 2026-11-18
---

# Tier layering model — definitions, decisions, migration plan

This document describes the **7-tier layering model** Forge is adopting, the directory + GHCR convention that encodes tier membership in the path, every decision made so far, and the step-by-step migration plan across FG-067 → FG-071. It is the authoritative reference while the migration is in flight. Once FG-071 ships, the "definitions" section of this doc moves to `memory/docker-standard.md` and this file becomes a historical record.

---

## 1. Context + motivation

### Problem

Today's directory layout is flat — every image lives at `images/<name>/`. Tier membership (pre-builder, builder, baseline, runtime, mirror, source) is encoded in Python/shell sets scattered across six scripts (`verify-dockerfile-conformance.py` `_PRE_BUILDERS`/`_FORGE_BUILDERS`/`_FORGE_MIRRORS`, `discover-images.sh` `_PRE_BUILDERS`/`_FORGE_BUILDERS`, `image_from_graph.py` `_PRE_BUILDERS`/`_FORGE_BUILDERS`/`_FORGE_MIRRORS`/`_UPSTREAM_HELPERS`). Adding a new tier member requires editing all of them + updating the dep-graph emitter.

### Secondary problems identified

- **Hidden intra-layer edges**: `beaconry-*` → `python-scratch-trixie` is an L4-to-L4 edge that bypasses the conformance lint's downward-only invariant, because beaconry images are externally-sourced (FG-012) and the lint only inspects local Dockerfiles.
- **Asymmetric scratch runtime construction**: `healthy-scratch-trixie` doesn't overlay `scratch-base-trixie` like the other 9 scratch runtimes do — no documented reason today.
- **Blurred semantics**: "pre-builder" / "builder" / "baseline" are used colloquially with partial overlap. Need crisp definitions for new contributors.
- **No tier for "externally-sourced + utility-sidecar" images**: beaconry + healthy don't fit cleanly in L4 (standard-construction runtimes).

### Solution — formalize tiers via directory prefix

Tier membership becomes **self-evident from the directory path**. `images/<tier>/<name>/` encodes the tier in the folder structure. GHCR repo paths mirror the directory layout (nested): `ghcr.io/bboortz/<tier>/<name>:<tag>`. New images land in the right tier by convention, not by editing six sets. Tooling walks nested paths (already supported for `mirror/` since FG-066).

---

## 2. The 7-tier model at a glance

| Tier | Prefix | Role | Members (post-migration) |
|------|--------|------|--------------------------|
| **L0** | — (external) | Upstream **images** not forge-owned | Docker Hub bases, `anchore/syft`, `nginx:1.31.9-alpine-slim`, `ghcr.io/bboortz/hc` (forge-owned helper, stays flat) |
| **L0.1** | — (external) | Upstream **source repositories / release tarballs** consumed by Forge builds | `github.com/bboortz/beaconry` (git), `github.com/google/cadvisor` (git), `github.com/prometheus/prometheus` (git), `ziglang.org/download/*.tar.xz`, upstream release tags resolved by `build.ref-latest-release` |
| **L0.5** | `mirror/` | Forge-signed zero-mod passthroughs of external tool images | `mirror/syft` |
| **L1** | `pre-builder/` | Forge-signed thin variants of upstream OS bases | 7 pre-builders (including `zig-slim-trixie` — FG-072) |
| **L2** | `builder/` | Development toolchains (never runtime) | 4 builders (python, go, node, zig — zig added by FG-072) |
| **L3** | `base/` | Scratch-assembled runtime foundations consumed by other forge images | `base/scratch-base-trixie`, `base/python-scratch-trixie` |
| **L4** | — (no prefix) | Consumer-facing runtimes with zero forge-internal consumers — includes from-source + externally-sourced images | ~17 runtimes |

**Note on L4 absorbing source-built images (updated 2026-11-20)**: Images that are *consumer-facing runtimes* and happen to be built from external source — `beaconry-{hub,scout,telegram-mock}` (FG-012 externally-sourced), `healthy-scratch-trixie` (utility sidecar), and from-source Go/Node builds like `cadvisor-slim-trixie`, `prometheus-scratch-trixie`, `alertmanager-scratch-trixie`, etc. — all live in L4 with no prefix. "Where the source came from" is a build-time detail; "is this what an operator pulls?" is the tier semantic. The upstream source repos themselves are classified as L0.1.

---

## 3. Layer definitions (full detail per tier)

Each layer has a **🔑 one-line semantic test** that resolves membership unambiguously. The tests evaluate top-down: if an image passes the test for layer N, stop; don't check lower layers.

### L0 — Upstream images

| Property | Value |
|---|---|
| **One-line definition** | Any **container image** whose publish identity is NOT under `ghcr.io/bboortz/{mirror,pre-builder,builder,base}/...` AND is NOT a flat forge L4 image |
| **What's inside** | Whatever the upstream maintainer built |
| **Built by** | Not Forge |
| **Forge-signed?** | No (operator trusts the upstream + their signing story) |
| **Runs at runtime?** | Irrelevant to Forge |
| **Dockerfile shape** | Not Forge's concern |
| **Build time** | N/A |
| **Published under** | `docker.io/*`, `ghcr.io/<other-org>/*` |
| **Consumed by** | L0.5 mirrors (FROM); L1 pre-builders (FROM); L4 postgres-slim-trixie + nginx-scratch-alpine (dedicated runtime exemptions — `postgres:18`, `nginx:1.31.9-alpine-slim`) |
| **Members** | `debian:trixie-slim`, `debian:sid-slim`, `python:3.14-slim-trixie`, `ubuntu:24.04`, `node:24-trixie-slim`, `golang:1.27-trixie`, `postgres:18`, `nginx:1.31.9-alpine-slim`, `anchore/syft:latest`, `ghcr.io/bboortz/hc:0.1.0` (forge-owned helper; stays at flat path, not under tier prefix) |
| **🔑 Semantic test** | "Is this a **container image** whose publish identity is not under a forge tier prefix?" → L0 |

### L0.1 — Upstream sources

| Property | Value |
|---|---|
| **One-line definition** | **Source code / release tarball** fetched by Forge builds at build time (not an image, not stored in GHCR) |
| **What's inside** | Git-cloned source tree or extracted tarball; compiled by a Forge L2 builder into a binary that lands in an L4 runtime overlay |
| **Built by** | Not Forge (we're the consumer; upstream maintains the source) |
| **Forge-signed?** | No — Forge records the commit SHA / tarball SHA256 in the derived L4 image's `org.opencontainers.image.revision` label + SBOM |
| **Runs at runtime?** | No — source is build-time input only |
| **Dockerfile shape** | N/A — source lives outside Dockerfiles. Consumed via `image.yaml source:` (FG-012 externally-sourced pattern) OR `RUN git clone` + `make` / `go build` / `zig build` in an L2 builder stage (FG-013 / FG-046 / FG-048 / future hc migration) OR `RUN curl` + tarball SHA256 verify (FG-050 / FG-072 Zig pattern) |
| **Build time** | Measured in seconds (clone) / seconds-to-minutes (compile — attributed to the derived L4 image's build) |
| **Pinning mechanism** | `source.ref:` field in `image.yaml` (FG-012); build-time `curl` against GitHub Releases API with jq-extracted tag (FG-013 `build.ref-latest-release`); committed SHA256 for tarballs (FG-072 `ARG ZIG_SHA256`) |
| **Consumed by** | L2 builders (as the source input to compile); L4 externally-sourced runtimes (FG-012 `source:` block) |
| **Members** | `github.com/bboortz/beaconry` (feeds beaconry-hub/scout/telegram-mock); `github.com/google/cadvisor` (cadvisor-slim-trixie); `github.com/prometheus/prometheus` + `prometheus/alertmanager` + `prometheus/node_exporter` + `prometheus-community/ipmi_exporter` (Go-source derivatives); `github.com/louislam/uptime-kuma` (uptime-kuma-slim-trixie); `github.com/actions/runner` (github-runner-noble); `ziglang.org/download/<ver>/zig-x86_64-linux-<ver>.tar.xz` (zig-slim-trixie); `github.com/bboortz/hc` (feeds `healthy-scratch-trixie`'s from-Zig-source build via `forge-builder-zig-trixie` — follow-up FG unblocked by FG-072; see § L2 flow below). |
| **Supply-chain surface** | Git host (GitHub) — availability, commit immutability. SHA256 for tarballs. CVE tracking: NOT via grype's OS matchers; via the derived L4 image's Go-module / npm / PyPI SBOM cataloger. |
| **🔑 Semantic test** | "Is this a **source repository or tarball URL** that a Forge build clones/fetches, rather than an image pulled by `docker pull`?" → L0.1 |

### L0.5 — Mirrors (`mirror/` prefix)

| Property | Value |
|---|---|
| **One-line definition** | Forge-signed **zero-mod passthrough** of an external tool image |
| **What's inside** | Bit-identical content to upstream + forge OCI labels + cosign signature. **Nothing else.** |
| **Dockerfile shape** | ONLY `FROM upstream`, `ARG`, `LABEL`, and (optionally) `COPY --from=<stage>`. Enforced by `verify-dockerfile-conformance.py` **Rule 10** (FG-066). |
| **Built by** | Forge (trivial — the FROM does all the work) |
| **Forge-signed?** | Yes |
| **Build time** | Seconds (no new content layers besides labels) |
| **Runs at runtime?** | **Never** — consumed ONLY via `COPY --from=<name>` in builder stages. No runtime use case. |
| **Dockerfile FROM** | External tool image (`anchore/syft:latest`, future `anchore/grype:latest`, etc.) |
| **Consumed by** | L2 builders (COPY --from) |
| **Size budget** | Upstream × 1.1 (label overhead only) |
| **Members** | `mirror/syft` |
| **Future candidates** | `mirror/grype`, `mirror/hadolint`, `mirror/terraform`, `mirror/cosign-cli` |
| **🔑 Semantic test** | "Is the Dockerfile restricted to `FROM` + `ARG` + `LABEL` + `COPY --from=` (nothing else) AND is the image under `images/mirror/*/`?" → Mirror |

### L1 — Pre-builders (`pre-builder/` prefix)

| Property | Value |
|---|---|
| **One-line definition** | Forge-signed **thin variant of an upstream OS base** |
| **What's inside** | Upstream OS layers + `apt-get upgrade` + `ca-certificates` + `dumb-init`. Keeps full shell, apt, package manager. |
| **Dockerfile shape** | `FROM <upstream-literal>` (single stage) + apt-upgrade RUN block. One or two LABEL blocks. |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Build time** | Seconds (one apt layer on top of cached upstream base) |
| **Runs at runtime?** | **Yes** — operators can `docker run -it <image> bash` and get a usable shell |
| **Dockerfile FROM** | L0 upstream (literal — grep-matched by `verify-no-upstream-drift.sh`) |
| **Consumed by** | L2 builders (FROM — dogfood); some L4 slim runtimes (FROM) |
| **Size budget** | Upstream × 1.1 (70–250 MB) |
| **Members (7)** | `pre-builder/debian-slim-trixie`, `pre-builder/debian-slim-sid`, `pre-builder/go-slim-trixie`, `pre-builder/node-slim-trixie`, `pre-builder/python-slim-trixie`, `pre-builder/ubuntu-slim-noble`, `pre-builder/zig-slim-trixie` (FG-072; tarball-install exception — FROMs debian-slim-trixie, installs Zig 0.17.1 from ziglang.org via committed SHA256) |
| **🔑 Semantic test** | "Does this image FROM an upstream OS base AND its only additions are apt-upgrade + ca-certs + dumb-init?" → Pre-builder |

### L2 — Builders (`builder/` prefix)

| Property | Value |
|---|---|
| **One-line definition** | **Development toolchain** for from-source compiles — never runs in production |
| **What's inside** | A pre-builder + `git` + `curl` + `jq` + `syft` (via mirror/syft) + language-specific tools (`make`+`g++`+`python3` for node native modules, `corepack` for npm/pnpm/yarn, upstream `go` toolchain, etc.) |
| **Dockerfile shape** | Multi-stage: `FROM mirror/syft AS syft-src` (COPY source) → `FROM pre-builder/<lang>-slim-trixie` (main) + apt-install block + `COPY --from=syft-src /syft /usr/local/bin/syft` |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Build time** | Minutes (multiple apt installs + syft install) |
| **Runs at runtime?** | **Never** — exists solely to be used as a multi-stage builder (`FROM builder/<X> AS builder` + `COPY --from=builder /artifact ...` in downstream Dockerfiles) |
| **Dockerfile FROM** | L1 pre-builder (dogfood per FG-065 `arch.language-family-image-pair` invariant) |
| **Consumed by** | L3 bases (as builder stage); many L4 runtimes (as builder stage); L4.5 healthy-scratch (as builder stage) |
| **Published for `docker pull`?** | Yes (CI publishes it as a published artifact), but no production operator pulls it |
| **Size budget** | 400–900 MB (toolchain-fat) |
| **Members (4)** | `builder/python-trixie`, `builder/go-trixie`, `builder/node-trixie`, `builder/zig-trixie`. The `forge-builder-` prefix was dropped per O1 (resolved). Zig added by FG-072; satisfies `arch.language-family-image-pair` as the 4th family. |
| **🔑 Semantic test** | "Does this image install development tools (git, compilers, package managers, syft) that would be useless or dangerous in a production runtime?" → Builder |

#### Worked example: L0.1 → L2 → L4 flow (Zig-source `/hc`)

Illustrates how all three tiers compose for a from-source runtime, using the upcoming hc migration into forge:

```
L0.1  github.com/bboortz/hc                       (source repo — git clone target)
         │
         │  cloned by  forge-builder-zig-trixie   (L2)
         │  compiled with  zig build              (produces static-musl binary `/hc`)
         ▼
L4    healthy-scratch-trixie                      (consumer-facing runtime)
         └─ Dockerfile builder stage:
              FROM ${FORGE_BUILDER_ZIG_REF} AS hc-builder
              RUN git clone https://github.com/bboortz/hc /src && \
                  cd /src && zig build -Doptimize=ReleaseSmall
              # /src/zig-out/bin/hc  →  overlay target  /hc
         └─ Runtime stage:
              FROM scratch
              COPY --from=hc-builder /src/zig-out/bin/hc  /hc
              ENTRYPOINT ["/hc"]
```

Why this classification is correct under the 7-tier model:

- **`github.com/bboortz/hc`** is **L0.1** — a source repo fetched via `git clone` at build time. Not published as an image, not stored in GHCR. Pinning via `source.ref:` or a build-time `curl + jq` tag resolver.
- **`forge-builder-zig-trixie`** is **L2** — pure build-time tool. Nobody `docker run`s it. It ships `zig` + `git` + `curl` + `jq` + `syft` for assembling the overlay.
- **`healthy-scratch-trixie`** is **L4** — the consumer-facing runtime. The fact that its construction involves an upstream source repo (L0.1) + a forge builder (L2) is a build-time detail; its tier is defined by "operator pulls this and runs it."

The current `healthy-scratch-trixie` Dockerfile uses a different L0-based path (`COPY --from=ghcr.io/bboortz/hc:0.1.0 /hc /hc` — the hc binary is pulled as an **image**, not built from source). FG-072 unblocks the migration from that L0-image path to the L0.1-source path shown above. Both land in L4 — only the builder-stage mechanism changes.

### L3 — Bases (`base/` prefix)

| Property | Value |
|---|---|
| **One-line definition** | **Runtime foundation** — assembled `FROM scratch` with curated closure, consumed by downstream forge images |
| **What's inside** | ONLY what runtime needs — no shell, no apt, no package manager. Starts `FROM scratch` and selectively `COPY --from=builder` the required libs/binaries/configs. |
| **Dockerfile shape** | Multi-stage: `FROM builder/<X> AS builder` (does the heavy lifting: builds Python/Node/etc. from source OR curates glibc closure) → `FROM scratch` runtime + `COPY --from=builder /curated/* /*`. |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Build time** | Minutes (COPY of curated closure + any from-source library builds) |
| **Runs at runtime?** | **Yes**, but limited — no shell means no `docker exec -it bash` debugging. Operators who run it do so programmatically. |
| **Dockerfile FROM** | `FROM scratch` (final stage); uses a L2 builder for the build stage |
| **Consumed by** | **At least one forge-internal consumer exists** (overlay via COPY --from= OR FROM-parent of another forge image). This is the distinguishing property from L4. |
| **Size budget** | 10–45 MB (tight — only runtime closure) |
| **Members (2)** | `base/scratch-trixie` (shared glibc+CA+nss overlay for every scratch runtime — formerly `scratch-base-trixie`); `base/python-trixie` (python interpreter + stdlib assembled on scratch — parent for beaconry-* — formerly `python-scratch-trixie`). Renames applied in FG-069 per O2+O3 (resolved). |
| **Future candidates** | `base/node-scratch-base` (only if a from-source Node scratch runtime appears — today zero consumers) |
| **Explicit non-candidate** | `base/go-scratch-base` — Go produces fully static binaries; the runtime closure is empty; scratch + the binary is sufficient. |
| **🔑 Semantic test** | "Does this image start `FROM scratch`, assemble a curated runtime closure, AND does at least one OTHER forge image consume it (as overlay via COPY --from= OR as FROM-parent)?" → Base |

### L4 — Runtimes (no prefix, consumer-facing)

| Property | Value |
|---|---|
| **One-line definition** | **Consumer-facing single-purpose runtime** — the END of Forge's dependency chain. Includes both apt-installed (fast-build) and from-source (built via L2 builder) variants. |
| **What's inside** | One specific application + its runtime closure. Either slim (OS + app) or scratch (minimal + app). Source may come from Debian apt (fast-build pattern), from upstream GitHub source (L0.1 pattern via FG-012 `source:` block or FG-046/FG-048 git-clone-in-builder pattern), or from an upstream tarball (FG-072 Zig pattern). The construction mechanism is build-time detail; runtime role is the tier semantic. |
| **Dockerfile shape** | Standard patterns, any of: (a) slim = `FROM pre-builder/<X>` + apt-install + app; (b) scratch = multi-stage `FROM builder/<X> AS builder` → `FROM scratch` + `COPY --from=base/scratch-base-trixie / /` overlay + `COPY --from=builder /artifact`; (c) FG-012 externally-sourced = `image.yaml source:` block + no local Dockerfile (upstream's Dockerfile cloned from L0.1); (d) sidecar/non-standard = local Dockerfile that opts out of SBT overlay for size/role reasons (e.g. `healthy-scratch-trixie`). |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Build time** | Varies (seconds for apt-slim; minutes for from-source scratch + UI compile) |
| **Runs at runtime?** | **Yes** — this is what operators pull and deploy |
| **Dockerfile FROM** | L1 pre-builder (slim runtimes) OR L3 base (scratch runtimes) OR L0 upstream (dedicated exemption — `postgres-slim-trixie`, `nginx-scratch-alpine`) OR L0.1 source clone via FG-012 (`beaconry-*`) |
| **Consumed by** | **ZERO forge-internal consumers.** External consumers (homelab, Beaconry, operators) pull them. |
| **Published under** | `ghcr.io/bboortz/<name>` (flat — no prefix) |
| **Size budget** | Varies (400 KB `healthy-scratch-trixie` → 600+ MB `github-runner-noble`) |
| **Members (~17)** | Debian-apt-slim / scratch: `cadvisor-slim-trixie`, `github-runner-noble`, `uptime-kuma-slim-trixie`, `nginx-scratch-trixie`, `redis-scratch-trixie`, `mosquitto-scratch-trixie`, `ipmi-exporter-slim-trixie`, `ipmi-exporter-scratch-trixie`, `postgres-slim-trixie`, `postgres-scratch-trixie`. From-Go-source via L2 `builder/go-trixie`: `prometheus-scratch-trixie`, `alertmanager-scratch-trixie`, `node-exporter-scratch-trixie`. Externally-sourced via FG-012 (git-clone from L0.1 `github.com/bboortz/beaconry`): `beaconry-hub`, `beaconry-scout`, `beaconry-telegram-mock`. From-Zig-source via L2 `builder/zig-trixie` (post hc-migration follow-up FG): `healthy-scratch-trixie` — currently COPYs `/hc` from external `ghcr.io/bboortz/hc:0.1.0`; migrates to a builder stage that clones L0.1 `github.com/bboortz/hc`, compiles with `zig build` inside `forge-builder-zig-trixie`, and overlays the resulting static-musl binary into the scratch runtime. Alpine-upstream runtime (FG-073): `nginx-scratch-alpine`. |
| **🔑 Semantic test** | "Is this image consumer-facing (pulled by external operators) AND has ZERO forge-internal consumers (no other `images/*/` references it)?" → Runtime |

> **2026-11-20 revision**: The previously-proposed `L4.5 — Source-builds (source/ prefix)` tier is **retired**. The construction mechanism (apt vs clone-source vs tarball) is a build-time detail of the derived L4 image; it does not warrant its own tier. The upstream source repos themselves are classified as L0.1. FG-012 externally-sourced images (`beaconry-*`) and from-source Go/Node derivatives (`prometheus-scratch-trixie`, etc.) stay at flat `images/<name>/` paths published to `ghcr.io/bboortz/<name>:<tag>`. The migration plan in §7 FG-068 is correspondingly simplified — see below.

---

## 4. Overlap resolution — every pair examined

| Pair | Could an image be both? | Distinguishing property |
|------|------------------------|-------------------------|
| L0 ↔ L0.1 | No — L0 is a published container image; L0.1 is source code / tarball | Transport (`docker pull` vs `git clone` / `curl .tar.xz`) |
| L0 ↔ L0.5 | No — mirrors are forge-signed republishes, not external | Publish identity (`ghcr.io/bboortz/mirror/...` only is a mirror) |
| L0.1 ↔ L0.5 | No — L0.1 isn't an image at all | Transport test again |
| L0 / L0.1 ↔ anything ≥ L1 | No — tier ≥ L1 members are forge-published GHCR images or flat forge runtimes | Publish identity + forge-ownership |
| L0.5 ↔ L1 | No — mirror has no apt-upgrade; pre-builder has one | Rule 10 (zero-mod enforcement) |
| L0.5 ↔ L2 | No — mirror has no toolchain | Rule 10 enforces |
| L0.5 ↔ L3 | No — mirror never has a `FROM scratch` runtime stage | Rule 10 enforces |
| L0.5 ↔ L4 | No — mirror has no application payload | Rule 10 + shape |
| L1 ↔ L2 | No — pre-builder has no dev tools | Presence of `git`+`make`+`g++`+`syft` ⇒ builder |
| L1 ↔ L3 | No — pre-builder keeps upstream OS layers; base is `FROM scratch` | Final-stage FROM target |
| L1 ↔ L4 | Theoretically could overlap if an L4 slim runtime equals a pre-builder, but pre-builders don't carry a specific application | "Does it package a specific app?" ⇒ L4 if yes |
| L2 ↔ L3 | No — builder runs only at build time (discarded); base ships as runtime | "Runs at runtime?" ⇒ No ⇒ builder |
| L2 ↔ L4 | No — builders have no app payload | App payload ⇒ L4 |
| L3 ↔ L4 | **Edge case** — `python-scratch-trixie` could be either. **Resolved by**: "has ≥ 1 forge-internal consumer" ⇒ L3; zero ⇒ L4 | `beaconry-*` FROM `python-scratch-trixie` → `python-scratch-trixie` is L3 |

### Key semantic principles (ordered)

1. **L0 Upstream image vs L0.1 Upstream source** → "fetched via `docker pull` or `git clone` / `curl`?" If image, L0; if source, L0.1. Both are upstream; the transport distinguishes them.
2. **L0.5 Mirror vs L1 Pre-builder** → "zero content modifications?" (Rule 10). If yes, mirror; if any RUN, pre-builder or lower.
3. **L2 Builder** → "runs at runtime?" test. If no (only used in multi-stage builder), it's a builder.
4. **L3 Base vs L4 Runtime** → "has forge-internal consumers?" test. If yes, base; if no, runtime.
5. **L4 includes both apt-installed AND from-source builds** → Construction mechanism is build-time detail; runtime role is the tier semantic. A from-source Go runtime that nobody else consumes is still an L4 runtime, not a separate "source" tier. Same rule applies to from-Zig-source runtimes built via L2 `builder/zig-trixie` (future `healthy-scratch-trixie` post hc-migration — see § "Worked example: L0.1 → L2 → L4 flow").
6. **L0 Upstream image vs everything else** → "published under `ghcr.io/bboortz/{mirror,pre-builder,builder,base}/` or flat L4?" If no, upstream image (L0).

---

## 5. Decisions locked

| # | Decision | Rationale | Alternative rejected |
|---|----------|-----------|----------------------|
| **D1** | Formalize 7-tier model | Current ad-hoc classification spread across 6 scripts' sets is error-prone | Keep flat with sets — but every new image requires 6 script updates |
| **D2** | Encode tier in directory prefix (`images/<tier>/<name>/`) | Path self-documents tier membership; new images land in the right place by convention | Keep flat dirs + keep scripts' sets — rejected per D1 |
| **D3** | Mirror GHCR paths = nested (`ghcr.io/bboortz/<tier>/<name>`) | Consistent with on-disk layout; clean story for future mirrors / bases | Flat GHCR + nested dirs via `repo:` override — rejected: half-measure, conflates convention |
| **D4** | `base/` holds all scratch-assembled runtime foundations | Clear criterion ("has forge-internal consumers" + "FROM scratch") disambiguates from L4 | Multiple sub-tiers for different base types — rejected: 2 members today, YAGNI |
| **D5** | `python-scratch-trixie` → `base/` (promoted from L4) | Has forge-internal consumer (beaconry-*) → meets L3 definition | Keep in L4 — rejected: hides the role, leaves intra-L4 edge |
| **D6** | `source/` holds externally-sourced + utility-sidecar runtimes | Covers both FG-012 (beaconry) and non-standard construction (healthy) | Only FG-012 externally-sourced — rejected: healthy would stay anomalous in L4 |
| **D7** | `healthy-scratch-trixie` → `source/` | Interpretation (A): healthcheck-sidecar category | Interpretation (B) catch-all exceptions — rejected: becomes dumping ground |
| **D8** | `hc` stays at `ghcr.io/bboortz/hc` (not under `mirror/`) | Forge-OWNED binary (built from `github.com/bboortz/hc` source), not a mirror of an external | Move to `mirror/hc` — rejected: different semantics; 11 consumers would break |
| **D9** | `postgres-slim-trixie` stays L4 (exempted from "FROM forge" rule) | Externally-maintained runtime; rebuilding from source is too big | Create `mirror/postgres` passthrough — rejected: regresses apt-upgrade value |
| **D10** | No `base/go-scratch-base` planned | Go produces fully static binaries → runtime closure is empty; `FROM scratch + binary` is sufficient | Create anyway for symmetry — rejected: zero consumers + no payload makes it useless |
| **D11** | `base/node-scratch-base` deferred | No from-source Node scratch runtime in the fleet today | Build pre-emptively — rejected: YAGNI |
| **D12** | Step-by-step migration (5 FGs) | Each FG has bounded blast radius; `source/` first (smallest) validates the tooling for the larger migrations | Big-bang single PR — rejected: too risky, hard to review |
| **D13** | Migration order: FG-067 foundation → FG-068 `source/` → FG-069 `base/` → FG-070 `pre-builder/` → FG-071 `builder/` | Ascending blast radius; each FG proves the pattern before applying to a larger set | Alphabetical / arbitrary order — rejected: wrong risk ordering |

---

## 6. Open points — need resolution BEFORE FG-067 ships

These decisions block starting the migration. List them here so they get answered explicitly.

### O1. Builder image naming — keep `forge-builder-` prefix or drop it? *(resolved — closed 2026-11-20)*

**Decision**: Option (b) — drop the prefix. `images/forge-builder-python-trixie/` → `images/builder/python-trixie/` → `ghcr.io/bboortz/builder/python-trixie:0.1`. Applied to all four L2 builders (python, go, node, zig).

Rationale: tier is encoded in the path prefix; repeating `forge-builder-` in the leaf is visually redundant and operators never pull builders by image reference (they're `COPY --from=` targets in Dockerfiles).

**Status**: **Closed.** Rename executed in FG-071.

### O2. Scratch-base-trixie renaming *(resolved — closed 2026-11-20)*

**Decision**: Drop the redundant `-base-` token. `images/scratch-base-trixie/` → `images/base/scratch-trixie/` → `ghcr.io/bboortz/base/scratch-trixie:0.2`.

Rationale: the `base/` tier prefix already encodes "scratch-assembled runtime foundation" per the L3 definition. `base/scratch-base-trixie` is visually redundant; `base/scratch-trixie` is clean.

**Status**: **Closed.** Rename executed in FG-069.

### O3. Python-scratch-trixie renaming *(resolved — closed 2026-11-20)*

**Decision**: Same rule — drop the redundant `-scratch-` token. `images/python-scratch-trixie/` → `images/base/python-trixie/` → `ghcr.io/bboortz/base/python-trixie:3.13`.

Rationale: the `base/` tier prefix means "scratch-overlay runtime foundation" (contrast: `pre-builder/python-slim-trixie` is slim-with-shell). Encoding scratch-vs-slim in both the prefix AND the leaf is noise.

**Note on consumer breakage**: this is a GHCR repo rename — every downstream consumer (Beaconry's three Dockerfiles + any external operator pulling python-scratch-trixie directly) updates their `FROM`. Handled per O5 (paired PR).

**Status**: **Closed.** Rename executed in FG-069.

### O4. Homelab coordination *(resolved — closed 2026-11-20)*

**Decision**: Each migration FG pairs with an immediately-after homelab PR. Forge PR lands first (tags move), homelab PR within ~1 hour (pulls newly-tagged images). No dual-publish (see O6).

**Status**: **Closed.** Workflow written into each migration FG's § "Coordinated PRs" line.

### O5. Beaconry coordination *(resolved — closed 2026-11-20)*

**Decision**: Same workflow as O4. FG-069 (base/ migration) pairs with a beaconry PR that updates the 3 Beaconry Dockerfiles' `FROM ghcr.io/bboortz/python-scratch-trixie:3.13` → `FROM ghcr.io/bboortz/base/python-trixie:3.13`. Opens simultaneously with the forge PR; merged after forge main publishes.

**Status**: **Closed.**

### O6. Backward compatibility window *(resolved — closed 2026-11-20)*

**Decision**: **No dual-publish.** Pair each migration with its coordinated downstream PR instead (per O4 + O5). Dual-publish would create a legacy-path exit ramp easy to leave in place forever.

**Status**: **Closed.**

### O7. L5 — "External consumer" tier? *(resolved — closed 2026-11-20)*

Original question: should external consumer deployments (homelab, Beaconry server-side) be a tracked L5 inside Forge?

**Decision**: **Defer** (no L5 tier). Forge does not track external consumers — the dependency arrow runs from external → Forge, not the reverse. If a consumer needs to know which Forge images it depends on, it queries Forge's published dep graph (`docs/image-dependency-graph.{md,svg}` + `scripts/image_from_graph.py --emit=reverse-json`); Forge doesn't reach back.

**Status**: **Closed.** No tier change, no tooling change.

### O8. Rule enforcement for `source/` *(resolved — closed 2026-11-20)*

Original question: should `verify-dockerfile-conformance.py` enforce specific rules on L4.5 images?

**Resolution**: L4.5 is retired. The replacement Rule 11 (specified in §8) is a **negative guard**: no `source/` tier may be introduced in any directory / script / test / doc. L4 absorbs the from-source + externally-sourced runtimes; L0.1 captures the upstream source repos as first-class tier nodes in the dep graph, enforced by a new `scripts/verify-source-inventory.py` that cross-references `_UPSTREAM_SOURCES` against every `RUN git clone` + `image.yaml source:` reference.

**Status**: **Closed**. Implemented in FG-068.

### O9. CI tier naming *(resolved — closed 2026-11-20)*

Original question: should the `source/` tier get its own `publish-source` job?

**Resolution**: No `publish-source` job needed. From-source and externally-sourced runtimes live in L4 and publish through the existing `publish-derivatives` tier. L0.1 source repos are never published by Forge — they're external. The CI tier count stays at **5** (publish-mirrors ‖ publish-pre-builders → publish-builders → publish-base → publish-derivatives).

**Status**: **Closed**. No workflow change needed.

---

## 7. Step-by-step migration plan

Each step is a self-contained FG. Each FG:
- Opens one PR to `forge`
- Opens coordinated downstream PRs where O4 + O5 apply
- Ships as a complete unit (merge, release, publish)

### FG-067 — Foundation (policy + tooling, zero image moves)

**Scope**: Lock the layer definitions in docs. Update tooling to walk nested paths for ALL tiers (not just `mirror/`). No images move.

**Changes**:
1. `memory/docker-standard.md`: add § "7-tier layering model" with definitions from §3 of this doc.
2. `docs/CAPABILITIES.md`: NEW CAPs `arch.tier-prefix-convention`, `arch.layer-overlap-resolution`. Each documents the 🔑 semantic test.
3. `scripts/verify-dockerfile-conformance.py`: generalize `_FORGE_MIRRORS` pattern. Add `_BASE_IMAGES`, `_SOURCE_IMAGES` sets. Add new tier detection via directory prefix (`mirror/`, `pre-builder/`, `builder/`, `base/`, `source/`).
4. `scripts/discover-images.sh`: accept new tier modes (`mirrors`, `pre-builders`, `builders`, `base`, `source`, `base-runtimes`).
5. `scripts/image_from_graph.py`: emit new subgraphs for L3 base + L4.5 source (empty until FG-068+).
6. `scripts/build-image.sh`: no changes needed (already handles nested paths from FG-066).
7. Tests FG-019/FG-042/FG-057/FG-010/FG-064: already updated in FG-066 to walk nested; no further changes.

**Blast radius**: zero image moves, zero consumer contracts broken.

**Acceptance**: `tests/acceptance/test_FG_067_tier-layering-foundation.sh` — asserts the layer definitions are in `memory/docker-standard.md`, the tier modes work in `discover-images.sh`, and the dep-graph emitter has placeholder subgraphs for L3 + L4.5.

**Dependencies**: O1, O2, O3, O6, O7, O8, O9 resolved.

### FG-068 — `source/` tier migration (smallest blast)

**Scope**: Move 4 images: `beaconry-hub`, `beaconry-scout`, `beaconry-telegram-mock`, `healthy-scratch-trixie`.

**Changes**:
1. `git mv images/beaconry-hub images/source/beaconry-hub` (+ 2 other beaconry + healthy)
2. `image.yaml` of each: no change needed (`source:` block stays the same for beaconry; healthy keeps its local Dockerfile)
3. GHCR repo paths change: `ghcr.io/bboortz/beaconry-hub` → `ghcr.io/bboortz/source/beaconry-hub`. `repo:` field in `image.yaml` is implicit (basename logic), so may need explicit `repo: source/beaconry-hub` override.
4. `.github/workflows/build.yml`: add new `publish-source` job (needs `publish-base`), matrix from `discover-images.sh source`
5. `docs/CAPABILITIES.md`: NEW CAPs `build.l0-1-source-inventory`, `arch.l4-absorbs-from-source`
6. `memory/design-decisions.md`: add § "L0.1 upstream sources" with members + CVE-tracking strategy
7. Dep-graph regen: L0.1 subgraph shows source repos as nodes (dashed edges to their consumer L2 builders or L4 runtimes)

**Blast radius**: 
- Forge internal: 0 Dockerfile changes (the retirement of `L4.5 source/` means beaconry-* + healthy-scratch stay at `images/<name>/` → `ghcr.io/bboortz/<name>:<tag>`)
- External: zero — no consumer references change

**Coordinated PRs**: none.

**Acceptance**: `tests/acceptance/test_FG_068_l0-1-source-tier.sh` — asserts: (a) dep-graph emitter recognizes L0.1 nodes for every source repo listed in `_UPSTREAM_SOURCES`; (b) `discover-sources.sh` enumerates the expected ~8 source repos; (c) `scripts/verify-source-inventory.py` cross-references every Dockerfile's `RUN git clone` + every `image.yaml source:` block against `_UPSTREAM_SOURCES`; (d) no reference to a `source/` directory exists anywhere in scripts/tests/docs (safety guard against the retired tier concept resurfacing).

> **Scope note (2026-11-20 revision)**: FG-068's original scope was "move beaconry + healthy-scratch into `images/source/`". That tier was retired when the user chose "L4 absorbs from-source runtimes; upstream source repos are L0.1". FG-068 is now tooling-only — it formalizes L0.1 as a first-class tier in the dep graph without moving any image. Blast radius drops from "coordinate homelab + beaconry PRs" to zero. This is a strict win.

### FG-069 — `base/` tier migration

**Scope**: Move + rename the 2 L3 base images per O2+O3 resolutions.

**Changes**:
1. `git mv images/scratch-base-trixie images/base/scratch-trixie` (**leaf rename**: `-base-` token dropped)
2. `git mv images/python-scratch-trixie images/base/python-trixie` (**leaf rename**: `-scratch-` token dropped)
3. `repo:` override in each `image.yaml`: `repo: base/scratch-trixie`, `repo: base/python-trixie`
4. GHCR repo paths: `ghcr.io/bboortz/scratch-base-trixie` → `ghcr.io/bboortz/base/scratch-trixie`; `ghcr.io/bboortz/python-scratch-trixie` → `ghcr.io/bboortz/base/python-trixie`
5. Every scratch runtime's Dockerfile: `ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest` → `ARG SCRATCH_BASE_REF=ghcr.io/bboortz/base/scratch-trixie:0.2` — ~10 Dockerfiles. ARG name `SCRATCH_BASE_REF` kept (semantic — "the scratch base").
6. Beaconry's Dockerfiles (in the beaconry repo, NOT in forge): `FROM ghcr.io/bboortz/python-scratch-trixie:3.13` → `FROM ghcr.io/bboortz/base/python-trixie:3.13` — 3 beaconry Dockerfiles (hub, scout, telegram-mock). Coordinated PR per O5.
7. `.github/workflows/build.yml`: `publish-base` job matrix from `discover-images.sh base` (new mode).
8. `docs/CAPABILITIES.md`: NEW CAPs `build.base-tier`, `arch.base-tier-images`.
9. `_KNOWN_REF_ARGS` in `verify-dockerfile-conformance.py` stays unchanged (ARG names aren't renamed).
10. **README update**: the public-contract pull reference changes. Operators pulling `ghcr.io/bboortz/python-scratch-trixie:3.13` must migrate to `ghcr.io/bboortz/base/python-trixie:3.13`. Documented in the README's `§ Images` table + migration note.

**Blast radius**:
- Forge internal: ~10 Dockerfile ARG-default updates (scratch runtimes)
- External: 3 beaconry Dockerfiles (coordinated PR per O5); any external `python-scratch-trixie` consumer (README migration note)
- Homelab: verify via grep — no direct consumer of `python-scratch-trixie` or `scratch-base-trixie` expected (these are forge-internal bases); if any surface, pair per O4.

**Coordinated PRs**:
- Beaconry PR: 3 Dockerfiles' `FROM` targets. Opens simultaneously with the forge PR.

**Acceptance**: `tests/acceptance/test_FG_069_base-tier-migration.sh` — asserts: (a) new paths exist; (b) old flat paths gone; (c) 10 scratch runtimes' ARG defaults updated; (d) Rule 12 (base images FROM scratch + have ≥1 forge-internal consumer) passes; (e) no residual `scratch-base-trixie` or `python-scratch-trixie` string in any Dockerfile or script.

### FG-070 — `pre-builder/` tier migration

**Scope**: Move 7 pre-builders (including `zig-slim-trixie` added by FG-072).

**Changes**:
1. `git mv` × 7 for the pre-builder directories (debian-slim-trixie, debian-slim-sid, go-slim-trixie, node-slim-trixie, python-slim-trixie, ubuntu-slim-noble, zig-slim-trixie)
2. `repo:` override in each `image.yaml` → `repo: pre-builder/<name>`
3. GHCR paths change: `ghcr.io/bboortz/<name>` → `ghcr.io/bboortz/pre-builder/<name>`
4. Every consumer of each pre-builder updates its `ARG *_SLIM_REF` default:
   - 4 forge-builders: `PYTHON_SLIM_REF`, `GO_SLIM_REF`, `NODE_SLIM_REF`, `ZIG_SLIM_REF` (the last via `zig-slim-trixie` dogfood per FG-072)
   - 4 L4 consumers: `DEBIAN_SLIM_REF` in cadvisor + ipmi-slim; `NODE_SLIM_REF` in uptime-kuma; `UBUNTU_SLIM_NOBLE_REF` in github-runner-noble
5. Homelab Dockerfiles that FROM `python-slim-trixie` directly: ~3-4 Dockerfiles in homelab — coordinated PR per O4
6. `.github/workflows/build.yml`: `publish-pre-builders` job matrix mode (discover auto-picks via new prefix)
7. `docs/CAPABILITIES.md`: EXT updates to `build.pre-builder-tier`
8. `scripts/verify-no-upstream-drift.sh`: `_EXPECTED=6` is unchanged by the move (ARG-indirect zig-slim-trixie doesn't match literal grep; the other 6 pre-builders still each FROM their upstream literal).

**Blast radius**:
- Forge internal: 8 Dockerfile ARG-default updates (4 builders + 4 L4 slim consumers)
- External: ~3-4 homelab Dockerfiles

**Coordinated PRs**:
- Homelab PR: update Dockerfiles that FROM `ghcr.io/bboortz/python-slim-trixie` (or any other pre-builder leaf directly).

**Acceptance**: `tests/acceptance/test_FG_070_pre-builder-tier-migration.sh` — asserts: (a) 7 new paths exist; (b) 7 old flat pre-builder paths gone; (c) `discover-images.sh pre-builders` returns 7 entries under `pre-builder/*`; (d) all consumer ARG defaults updated.

### FG-071 — `builder/` tier migration (last; biggest blast)

**Scope**: Move + rename 4 builders per O1 resolution (drop `forge-builder-` prefix).

**Changes**:
1. `git mv images/forge-builder-python-trixie images/builder/python-trixie` (+ go + node + **zig**)
2. `repo: builder/python-trixie` override in each `image.yaml` (+ go + node + zig)
3. GHCR paths change: `ghcr.io/bboortz/forge-builder-{python,go,node,zig}-trixie` → `ghcr.io/bboortz/builder/{python,go,node,zig}-trixie`
4. Every downstream Dockerfile's ARG default: `ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-python-trixie:0.1` → `ARG BUILDER_PYTHON_REF=ghcr.io/bboortz/builder/python-trixie:0.1` (+ go + node + zig). Rename the ARG too. **~18 Dockerfiles** affected (the ~15 existing scratch runtimes + zig's consumers that exist at FG-071 time — at minimum the follow-up hc-migration image if it's landed by then).
5. `_KNOWN_REF_ARGS` in `verify-dockerfile-conformance.py`: replace `FORGE_BUILDER_*_REF` with `BUILDER_*_REF` entries.
6. `scripts/build-image.sh`: rename all internal `FORGE_BUILDER_REF` references to `BUILDER_PYTHON_REF` / `BUILDER_GO_REF` / `BUILDER_NODE_REF` / `BUILDER_ZIG_REF` in the ref-resolution + build-arg wiring blocks.
7. `.github/workflows/build.yml`: `publish-builders` matrix mode (no structural change — the discover filter picks up the new `builder/` prefix automatically).
8. `docs/CAPABILITIES.md`: EXT updates to `build.shared-{python,go,node,zig}-builder` (the CAP ids may stay; the GHCR paths they reference change).
9. **Dockerfile comments**: any inline docstring referencing `forge-builder-<lang>-trixie` by name gets refreshed to `builder/<lang>-trixie`. Grep sweep.
10. `memory/docker-standard.md` + `memory/design-decisions.md`: rename references.

**Blast radius**:
- Forge internal: ~18 Dockerfile ARG + name updates
- External: no homelab impact (builders are never consumed externally; builder images are COPY-from targets in Dockerfiles only).

**Coordinated PRs**: none external (per above).

**Acceptance**: `tests/acceptance/test_FG_071_builder-tier-migration.sh` — asserts: (a) 4 new paths exist; (b) 4 old `forge-builder-*` paths gone; (c) 0 Dockerfiles reference `forge-builder-` as a name token; (d) `_KNOWN_REF_ARGS` contains `BUILDER_{PYTHON,GO,NODE,ZIG}_REF`, no `FORGE_BUILDER_*_REF`; (e) 4 builders dogfood their respective pre-builders (FG-065 `arch.language-family-image-pair` still holds post-rename).

### Summary table

| FG | Images moved | Forge Dockerfile updates | External PRs needed | Risk |
|----|-------------|-------------------------|---------------------|------|
| FG-067 | 0 | 0 | 0 | 🟢 Low (policy + tooling only) |
| FG-068 | 0 (L0.1 tooling only; no `source/` tier) | 0 | None | 🟢 Low (pure tooling / dep-graph recognition) |
| FG-069 | 2 (base/) + 2 leaf renames | ~10 | Beaconry (3 Dockerfiles) | 🟡 Medium |
| FG-070 | 7 (pre-builder/) | 8 | Homelab (~3-4 Dockerfiles) | 🟡 Medium |
| FG-071 | 4 (builder/) + ARG renames | ~18 | None external | 🔴 High (biggest blast) |

---

## 8. Enforcement after migration

### Lint rules (enforced by `verify-dockerfile-conformance.py`)

1. **Rule 6** (FG-065): no intra-layer FROM edges — now checks all 7 tiers via directory prefix
2. **Rule 7** (FG-065): `builder/` images' last FROM resolves to a forge image (not upstream)
3. **Rule 8** (FG-065): literal `FROM <upstream>` allowed only in pre-builders + runtime-exemptions
4. **Rule 9** (FG-065): no `RUN`/`COPY`/`ADD` HTTP pulls from Docker Hub
5. **Rule 10** (FG-066): `mirror/` Dockerfiles are zero-mod (FROM + ARG + LABEL + COPY --from= only)
6. **Rule 11** (FG-068, NEW): no `source/` directory exists anywhere in `images/` / `scripts/` / `tests/` / `docs/` (post-retirement safety guard). Every string reference to a `source/` tier triggers a lint failure — forces authors to choose L0.1 (external repo) or L4 (runtime), not re-introduce a dead tier.
7. **Rule 12** (FG-069, NEW): `base/` images must FROM scratch (final stage) AND must have ≥ 1 forge-internal consumer

### Semantic tests in CI (`tests/acceptance/test_FG_<NN>_...sh`)

Each tier migration FG ships an acceptance test that proves:
- Directory structure matches the tier convention
- GHCR repo paths are nested correctly
- Downstream consumers reference the new paths
- Old flat paths are gone (no legacy references)
- The specific lint rules fire as expected

### Dep-graph validation

After every migration, `make dep-graph` regenerates `docs/image-dependency-graph.md` + `.svg`. The emitter shows each tier in its own subgraph (visual proof of layering).

---

## 9. Future work (NOT in migration scope)

These are tracked separately after FG-071 ships:

- **`mirror/grype`** — currently CI pulls grype fresh from Docker Hub each run; mirror it for the same reasons as syft.
- **`mirror/hadolint`, `mirror/shellcheck`, `mirror/terraform`** — currently fetched during `github-runner-noble` build; mirror if rate-limit pressure or supply-chain signing becomes material.
- **`base/node-scratch-base`** — only if a from-source Node scratch runtime appears.
- **`source/psitransfer`** — FG-062 draft; lands after FG-068.
- **New language-family pre-builders** (Rust? Zig?) — lands as `pre-builder/<lang>-slim-trixie` + `builder/<lang>-trixie` pair per the `arch.language-family-image-pair` invariant (FG-065).

---

## 10. Appendix — current → target path mapping

Complete table of every image's current and target path.

| Current path | Target path | Current GHCR repo | Target GHCR repo | Migration FG |
|-------------|-------------|-------------------|------------------|--------------|
| `images/mirror/syft/` | *(no change)* | `ghcr.io/bboortz/mirror/syft` | *(no change)* | — |
| `images/debian-slim-trixie/` | `images/pre-builder/debian-slim-trixie/` | `ghcr.io/bboortz/debian-slim-trixie` | `ghcr.io/bboortz/pre-builder/debian-slim-trixie` | FG-070 |
| `images/debian-slim-sid/` | `images/pre-builder/debian-slim-sid/` | `.../debian-slim-sid` | `.../pre-builder/debian-slim-sid` | FG-070 |
| `images/go-slim-trixie/` | `images/pre-builder/go-slim-trixie/` | `.../go-slim-trixie` | `.../pre-builder/go-slim-trixie` | FG-070 |
| `images/node-slim-trixie/` | `images/pre-builder/node-slim-trixie/` | `.../node-slim-trixie` | `.../pre-builder/node-slim-trixie` | FG-070 |
| `images/python-slim-trixie/` | `images/pre-builder/python-slim-trixie/` | `.../python-slim-trixie` | `.../pre-builder/python-slim-trixie` | FG-070 |
| `images/ubuntu-slim-noble/` | `images/pre-builder/ubuntu-slim-noble/` | `.../ubuntu-slim-noble` | `.../pre-builder/ubuntu-slim-noble` | FG-070 |
| `images/zig-slim-trixie/` | `images/pre-builder/zig-slim-trixie/` | `.../zig-slim-trixie` | `.../pre-builder/zig-slim-trixie` | FG-070 |
| `images/forge-builder-python-trixie/` | `images/builder/python-trixie/` | `.../forge-builder-python-trixie` | `.../builder/python-trixie` | FG-071 (O1→b) |
| `images/forge-builder-go-trixie/` | `images/builder/go-trixie/` | `.../forge-builder-go-trixie` | `.../builder/go-trixie` | FG-071 (O1→b) |
| `images/forge-builder-node-trixie/` | `images/builder/node-trixie/` | `.../forge-builder-node-trixie` | `.../builder/node-trixie` | FG-071 (O1→b) |
| `images/forge-builder-zig-trixie/` | `images/builder/zig-trixie/` | `.../forge-builder-zig-trixie` | `.../builder/zig-trixie` | FG-071 (O1→b) |
| `images/scratch-base-trixie/` | `images/base/scratch-trixie/` | `.../scratch-base-trixie` | `.../base/scratch-trixie` | FG-069 (O2 — `-base-` dropped) |
| `images/python-scratch-trixie/` | `images/base/python-trixie/` | `.../python-scratch-trixie` | `.../base/python-trixie` | FG-069 (O3 — `-scratch-` dropped) |
| L4 flat (~17 images) | *(no path change)* | `.../<name>` | *(no change)* | ARG updates in FG-069/070/071 |
| `images/beaconry-hub/` | *(no change — stays L4 flat)* | `.../beaconry-hub` | *(no change)* | — (source/ tier retired 2026-11-20) |
| `images/beaconry-scout/` | *(no change)* | `.../beaconry-scout` | *(no change)* | — |
| `images/beaconry-telegram-mock/` | *(no change)* | `.../beaconry-telegram-mock` | *(no change)* | — |
| `images/healthy-scratch-trixie/` | *(no change)* | `.../healthy-scratch-trixie` | *(no change)* | — |

### L0.1 upstream-source inventory (dep-graph only — no `images/` entry)

| Source | Consumed by | Pinning mechanism |
|--------|-------------|-------------------|
| `github.com/bboortz/beaconry` | `beaconry-hub`, `beaconry-scout`, `beaconry-telegram-mock` | `image.yaml source.ref: latest` (FG-012 + FG-013) |
| `github.com/google/cadvisor` | `cadvisor-slim-trixie` builder stage | FG-050 `build.ref-latest-release` |
| `github.com/prometheus/prometheus` | `prometheus-scratch-trixie` builder (dual-builder with Node) | FG-050 build-time tag resolution |
| `github.com/prometheus/alertmanager` | `alertmanager-scratch-trixie` builder (dual-builder) | FG-052 build-time tag resolution |
| `github.com/prometheus/node_exporter` | `node-exporter-scratch-trixie` builder | FG-046 pinned tag |
| `github.com/prometheus-community/ipmi_exporter` | `ipmi-exporter-{slim,scratch}-trixie` builder | FG-046/FG-043 pinned tag |
| `github.com/louislam/uptime-kuma` | `uptime-kuma-slim-trixie` builder | FG-045 + FG-013 build-time tag |
| `github.com/actions/runner` | `github-runner-noble` | FG-051 `build.ref-latest-release` |
| `ziglang.org/download/<ver>/zig-x86_64-linux-<ver>.tar.xz` | `zig-slim-trixie` builder (RUN curl) | FG-072 `ARG ZIG_VERSION` + `ARG ZIG_SHA256` |
| `github.com/bboortz/hc` | `healthy-scratch-trixie` builder stage (post hc-migration follow-up FG; compiles via `forge-builder-zig-trixie` → static-musl `/hc`); replaces the current `COPY --from=ghcr.io/bboortz/hc:0.1.0` L0-image path | follow-up FG: `source.ref:` or committed git-SHA |

---

## 11. Checklist before starting FG-067

- [x] **O1**: builder image prefix — **drop `forge-builder-`** → `builder/<lang>-trixie` (closed 2026-11-20)
- [x] **O2**: `scratch-base-trixie` → `base/scratch-trixie` (closed 2026-11-20 — `-base-` token dropped, encoded in tier prefix)
- [x] **O3**: `python-scratch-trixie` → `base/python-trixie` (closed 2026-11-20 — `-scratch-` token dropped, encoded in tier prefix)
- [x] **O4**: pair each migration FG with an immediately-after homelab PR (closed 2026-11-20)
- [x] **O5**: same workflow for beaconry — paired PR on FG-069 (closed 2026-11-20)
- [x] **O6**: no dual-publish (closed 2026-11-20)
- [x] **O7**: no L5 external-consumer tier — Forge doesn't track consumers; reverse-dep flow via published dep graph (closed 2026-11-20)
- [x] **O8**: ~~Rule 11 scope for source/ tier~~ — **CLOSED** (source/ tier retired; Rule 11 is now a negative guard)
- [x] **O9**: ~~`publish-source` CI tier~~ — **CLOSED** (no new CI tier; from-source runtimes publish via existing `publish-derivatives`)

**All 9 open points resolved.** No remaining blockers.

**FG-067 is unblocked.** Ready to start the foundation PR when you give the green light.
