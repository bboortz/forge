# The Forge 7-tier layering model

**Status**: authoritative reference (post-FG-075, 2026-11-21). Supersedes the "definitions" section of `docs/plan/tier-layering-model.md`, which now reads as the migration history.

**Audience**: Forge maintainers deciding where a new image belongs, downstream auditors verifying tier shape, and Claude sessions resolving ambiguity when adding or moving images.

---

## 1. Why we tier

Pre-FG-067, every Forge image lived at `images/<name>/` with its "role" (pre-builder, builder, baseline, runtime, mirror) encoded in Python/shell sets scattered across six scripts. Adding one image touched six files. Nothing stopped a reader from misclassifying `python-scratch-trixie` as a runtime when it was actually a base with downstream consumers. "Where does this go?" had no mechanical answer.

The 7-tier model makes **tier membership a property of the directory path**. `images/<tier>/<name>/` encodes the role; GHCR path mirrors it (`ghcr.io/bboortz/<tier>/<name>:<tag>`); conformance is CI-enforced by 12 rules in `scripts/verify-dockerfile-conformance.py`. A reader can determine any image's tier from `ls images/`.

---

## 2. The model at a glance

```
L4   flat runtimes               → consumer-facing; zero forge-internal consumers
                                   pulled by operators (homelab, Beaconry, ops)

L3   images/base/*/              → scratch-overlay runtime foundations
                                   consumed by ≥1 forge image (Rule 12)

L2   images/builder/*/           → language-family toolchains for from-source
                                   compiles; never run in production — COPY-from
                                   target in multi-stage builds only

L1   images/pre-builder/*/       → thin apt-upgrade + CA + dumb-init on upstream
                                   OS bases; keeps shell + apt + package manager

L0.5 images/mirror/*/            → zero-mod forge-signed passthroughs of external
                                   tool images (Rule 10)
                                   -----------------------------------------
L0.1 (no images/ dir; inventory  → upstream source code & tarballs fetched at
      in scripts/_upstream_         build time via git clone / curl .tar.xz
      sources.py)
                                   -----------------------------------------
L0   (no images/ dir; external)  → upstream OCI images pulled at build time
                                   (docker.io, foreign ghcr orgs)
```

**Key invariants** (enforced in CI):
- Chain depth from Docker Hub to any scratch runtime **≤ 5 hops** (FG-042)
- Exactly **6** literal `FROM <upstream>` lines across the fleet (`verify-no-upstream-drift.sh _EXPECTED=6`)
- Every path resolves to its tier by the directory prefix; no ambiguity

---

## 3. Tier definitions

Every tier has a **🔑 semantic test** — a single question that disambiguates membership. The tests evaluate top-down: if an image passes at tier N, stop; don't check lower tiers.

### L0 — Upstream images

| Property | Value |
|---|---|
| **Definition** | Any **container image** whose publish identity is NOT under `ghcr.io/bboortz/{mirror,pre-builder,builder,base}/*` AND is NOT a flat Forge L4 image |
| **Transport** | `docker pull` |
| **Built by** | Not Forge |
| **Forge-signed?** | No (operator trusts upstream's signing story) |
| **Dockerfile shape** | Not Forge's concern |
| **Consumed by** | L0.5 mirrors (`FROM`); L1 pre-builders (`FROM`); L4 runtime exemptions (`postgres-slim-trixie` → `postgres:18`, `nginx-scratch-alpine` → `nginx:1.31.9-alpine-slim` when FG-073 lands) |
| **Current members** | `debian:trixie-slim`, `debian:sid-slim`, `python:3.14-slim-trixie`, `ubuntu:24.04`, `node:24-trixie-slim`, `golang:1.27-trixie`, `postgres:18`, `anchore/syft:latest`, `ghcr.io/bboortz/hc:0.1.0` (forge-owned helper, stays flat outside the tier model) |
| **🔑 Semantic test** | *"Is this a container image whose publish identity is not under a Forge tier prefix?"* → L0 |

### L0.1 — Upstream sources

| Property | Value |
|---|---|
| **Definition** | **Source code** (git repo) or **release tarball** fetched by Forge builds at build time — not an image, not stored in GHCR |
| **Transport** | `git clone` (FG-012 `source:` block OR builder-stage `RUN git clone`), `curl <tarball>` + SHA256 verify (FG-072 Zig pattern) |
| **Built by** | Not Forge (we're the consumer) |
| **Forge-signed?** | No — the derived L4 image carries `org.opencontainers.image.revision=<resolved SHA>` as attestation |
| **Pinning mechanism** | `source.ref:` in `image.yaml` (FG-012); build-time `curl` against GitHub Releases API with jq (FG-013 `build.ref-latest-release`); committed SHA256 for tarballs (FG-072) |
| **Consumed by** | L2 builders (as compile input); L4 externally-sourced runtimes (FG-012 pattern) |
| **Inventory** | Registered in `scripts/_upstream_sources.py:_UPSTREAM_SOURCES`; two-way sync enforced by `verify-source-inventory.py` |
| **Current members (10)** | `github.com/bboortz/beaconry`, `github.com/google/cadvisor`, `github.com/prometheus/{prometheus,alertmanager,node_exporter}`, `github.com/prometheus-community/ipmi_exporter`, `github.com/louislam/uptime-kuma`, `github.com/actions/runner`, `github.com/tianon/gosu`, `ziglang.org/download` |
| **🔑 Semantic test** | *"Is this a source repository or tarball URL that a Forge build clones/fetches, rather than an image pulled by `docker pull`?"* → L0.1 |

### L0.5 — Mirrors (`mirror/` prefix)

| Property | Value |
|---|---|
| **Definition** | Forge-signed **zero-mod passthrough** of an external tool image |
| **Dockerfile shape** | ONLY `FROM`, `ARG`, `LABEL`, `COPY --from=<stage>`. Any other directive fails Rule 10. |
| **Built by** | Forge (trivial — the FROM does all the work) |
| **Forge-signed?** | Yes |
| **Runs at runtime?** | **Never** — consumed only via `COPY --from=` in builder stages |
| **FROM source** | L0 external tool image |
| **Consumed by** | L2 builders (COPY-from) |
| **Size budget** | Upstream × 1.1 (label overhead only) |
| **Current members (1)** | `mirror/syft` |
| **Future candidates** | `mirror/grype`, `mirror/hadolint`, `mirror/terraform`, `mirror/cosign-cli` |
| **🔑 Semantic test** | *"Is the Dockerfile restricted to `FROM` + `ARG` + `LABEL` + `COPY --from=` (nothing else) AND published under `ghcr.io/bboortz/mirror/`?"* → L0.5 |

### L1 — Pre-builders (`pre-builder/` prefix)

| Property | Value |
|---|---|
| **Definition** | Forge-signed **thin variant of an upstream OS base** |
| **Dockerfile shape** | Single stage: `FROM <upstream>` + one RUN block that does `apt-get upgrade` + install `ca-certificates` + install `dumb-init`. LABELs + optional `ENV`. |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Runs at runtime?** | **Yes** — `docker run -it <image> bash` works; operators get a shell |
| **FROM source** | L0 upstream (literal — grep-matched by `verify-no-upstream-drift.sh`) |
| **Consumed by** | L2 builders (dogfood per `arch.language-family-image-pair`); some L4 slim runtimes directly |
| **Size budget** | Upstream × 1.1 (70–250 MB) |
| **Current members (7)** | `pre-builder/debian-slim-trixie`, `pre-builder/debian-slim-sid`, `pre-builder/go-slim-trixie`, `pre-builder/node-slim-trixie`, `pre-builder/python-slim-trixie`, `pre-builder/ubuntu-slim-noble`, `pre-builder/zig-slim-trixie` |
| **One documented exception** | `pre-builder/zig-slim-trixie` FROMs `pre-builder/debian-slim-trixie` instead of a Zig upstream (none exists on Docker Hub); installs Zig from a committed-SHA256 tarball. Allowlisted via `_INTRA_LAYER_EXEMPTIONS`. |
| **🔑 Semantic test** | *"Does this image FROM an upstream OS base AND its only additions are apt-upgrade + ca-certs + dumb-init?"* → L1 |

### L2 — Builders (`builder/` prefix)

| Property | Value |
|---|---|
| **Definition** | **Language-family toolchain** for from-source compiles — never runs in production |
| **Dockerfile shape** | Multi-stage: `FROM ${SYFT_REF} AS syft-src` (COPY source) → `FROM pre-builder/<lang>-slim-trixie` (main) + `apt-get install` dev tools + `COPY --from=syft-src /syft /usr/local/bin/syft` |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Runs at runtime?** | **Never** — exists solely as a multi-stage builder (`FROM builder/<X> AS builder` in downstream Dockerfiles) |
| **FROM source** | L1 pre-builder sibling (Rule 7: builder's last FROM must resolve to a forge-rooted image; satisfied by the `arch.language-family-image-pair` invariant) |
| **Consumed by** | L3 bases (builder stage); L4 from-source runtimes (builder stage) |
| **Size budget** | 400–900 MB (toolchain-fat) |
| **Current members (4)** | `builder/python-trixie`, `builder/go-trixie`, `builder/node-trixie`, `builder/zig-trixie` |
| **Pairing rule** | Every L2 `builder/<lang>-trixie` MUST have a sibling L1 `pre-builder/<lang>-slim-trixie`. Enforced by `verify-dockerfile-conformance.py:_check_language_family_invariant`. |
| **🔑 Semantic test** | *"Does this image install development tools (git, compilers, package managers, syft) that would be useless or dangerous in a production runtime?"* → L2 |

### L3 — Bases (`base/` prefix)

| Property | Value |
|---|---|
| **Definition** | **Runtime foundation** — assembled `FROM scratch` with curated glibc/overlay closure, consumed by ≥1 downstream Forge image |
| **Dockerfile shape** | Multi-stage: `FROM builder/<X> AS builder` → `FROM scratch` runtime + `COPY --from=builder /curated/* /*` |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Runs at runtime?** | **Yes, but limited** — no shell, no `docker exec -it bash` debugging. Operators run them programmatically. |
| **FROM source (final stage)** | `FROM scratch` — enforced by **Rule 12** |
| **Consumer requirement** | **≥1 forge-internal consumer** (another image's `image.yaml depends_on:` lists it, OR another Dockerfile FROMs it, OR another Dockerfile COPYs from it) — enforced by Rule 12 |
| **Size budget** | 10–45 MB (tight — only runtime closure) |
| **Current members (2)** | `base/scratch-trixie` (9 consumers — shared glibc + CA + nss overlay for every scratch runtime), `base/python-trixie` (3 consumers — beaconry-*) |
| **One documented exception** | `base/python-trixie` FROMs `base/scratch-trixie` (intra-L3 edge) — the python overlay legitimately composes atop the scratch overlay. Allowlisted via `_INTRA_LAYER_EXEMPTIONS`. |
| **🔑 Semantic test** | *"Does this image start `FROM scratch`, assemble a curated runtime closure, AND does at least one other Forge image consume it?"* → L3. **If zero consumers, it belongs at the flat L4 position.** |

### L4 — Runtimes (flat path, no prefix)

| Property | Value |
|---|---|
| **Definition** | **Consumer-facing single-purpose runtime** — the end of Forge's dependency chain |
| **Dockerfile shape** | Any of four patterns: (a) **slim** = `FROM pre-builder/<X>` + apt-install + app; (b) **scratch** = multi-stage `FROM builder/<X>` → `FROM scratch` + `COPY --from=base/scratch-trixie / /` overlay + `COPY --from=builder /artifact`; (c) **externally-sourced** = `image.yaml source:` block + upstream's own Dockerfile cloned at build time (FG-012); (d) **upstream exemption** = `FROM <upstream>` directly (narrow allowlist only) |
| **Built by** | Forge |
| **Forge-signed?** | Yes |
| **Runs at runtime?** | **Yes** — this is what operators pull and deploy |
| **FROM source** | L1 pre-builder (slim) OR L3 base (scratch overlay) OR L0 upstream (allowlisted exemptions) OR L0.1 upstream source (FG-012 externally-sourced) |
| **Consumer requirement** | **ZERO forge-internal consumers** (if ≥1, it's an L3 base) |
| **Published under** | `ghcr.io/bboortz/<name>` (flat — no tier prefix) |
| **Size budget** | Varies (400 KB `healthy-scratch-trixie` → 600+ MB `github-runner-noble`) |
| **Current members (17)** | See `docs/image-dependency-graph.md`; grouped in §4 below by construction pattern |
| **Documented exemption** | `postgres-slim-trixie` FROMs `postgres:18` directly — rebuilding postgres from source is too big. Allowlisted via `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS`. |
| **🔑 Semantic test** | *"Is this image consumer-facing (pulled by external operators) AND has zero forge-internal consumers?"* → L4 |

---

## 4. L4 construction patterns

L4 is the widest tier; four sub-shapes exist but all share the "consumer-facing, zero forge-internal consumers" test. **The construction mechanism is a build-time detail, not a tier distinction.** The retired L4.5 `source/` tier (Rule 11) exists precisely to prevent anyone re-adding a sub-tier for mechanism.

| Pattern | FROM shape | Current examples |
|---|---|---|
| **(a) Debian apt-slim** | `FROM pre-builder/debian-slim-trixie` (or `ubuntu-slim-noble`) + apt-install the app | cadvisor-slim-trixie, github-runner-noble, uptime-kuma-slim-trixie, ipmi-exporter-slim-trixie, postgres-slim-trixie (upstream-exempt variant) |
| **(b) Debian apt-scratch** | Multi-stage: `FROM builder/python-trixie` → `FROM scratch` + overlay `base/scratch-trixie` + COPY curated apt binaries | nginx-scratch-trixie, redis-scratch-trixie, mosquitto-scratch-trixie, postgres-scratch-trixie, ipmi-exporter-scratch-trixie |
| **(c) From-source scratch** | Multi-stage: `FROM builder/<lang>-trixie` + clone L0.1 source + compile → `FROM scratch` + overlay + COPY artifact | prometheus-scratch-trixie, alertmanager-scratch-trixie, node-exporter-scratch-trixie, healthy-scratch-trixie (currently COPYs pre-built `/hc`; from-source migration pending) |
| **(d) Externally-sourced** (FG-012) | `image.yaml source:` block — Forge clones the git repo + builds via the upstream's own Dockerfile | beaconry-hub, beaconry-scout, beaconry-telegram-mock |

---

## 5. Overlap resolution

Every pair of adjacent tiers has one disambiguating property. Resolve from the top:

| Pair | Disambiguator | Example |
|---|---|---|
| L0 ↔ L0.1 | Transport (`docker pull` vs `git clone` / `curl .tar.xz`) | `anchore/syft:latest` is L0; `github.com/google/cadvisor` is L0.1 |
| L0 ↔ L0.5 | Publish identity (under `ghcr.io/bboortz/mirror/*`?) | `anchore/syft:latest` (L0) vs `mirror/syft` (L0.5) |
| L0.5 ↔ L1 | Rule 10 (has any `RUN`?) | mirror has no `RUN`; pre-builder has one apt-upgrade RUN |
| L1 ↔ L2 | Presence of dev tools (`git` + compilers + `syft`) | pre-builder has only apt-upgrade; builder adds toolchain |
| L1 ↔ L3 | Final-stage FROM target (upstream OS vs `scratch`) | pre-builder FROMs upstream; base FROMs scratch |
| L2 ↔ L3 | Runs at runtime? | builder never; base yes-but-limited |
| L2 ↔ L4 | App payload? | builder has none; L4 has one specific app |
| **L3 ↔ L4** | **≥1 forge-internal consumer?** | base: yes (Rule 12 enforces); L4: zero |

The **L3 ↔ L4 boundary is the only one that can shift over time**: if an L4 runtime gains a forge-internal consumer, it promotes to L3 (FG-069 did this for `python-scratch-trixie` → `base/python-trixie`). If an L3 base loses all consumers, it demotes to flat L4 (Rule 12 would trigger the demotion on the next conformance run).

---

## 6. CI-enforced rules

All rules live in `scripts/verify-dockerfile-conformance.py` unless noted. `make test-fast` + `make check` run every rule on every PR.

| Rule | Guarantee | Rationale |
|---|---|---|
| **1** | Every image has `image.yaml` with `tag:` + `platforms:` | Build determinism |
| **2** | Every image has `PROMISES.yaml` with ≥1 promise | FG-010 image-to-image contracts |
| **3** | Every promise references ≥1 smoke-test / preflight pointer | FG-010 traceability |
| **4** | Every `depends_on:` target exists | Build-graph soundness |
| **5** | No circular `depends_on:` | Build-graph acyclic |
| **6** | No intra-tier FROM edges (downward-only layered graph) | Layered dep-graph (FG-064) — narrow exemptions via `_INTRA_LAYER_EXEMPTIONS` |
| **7** | Every L2 `builder/<lang>-trixie`'s last FROM resolves to a forge-rooted image | FG-065 `arch.language-family-image-pair` dogfood invariant |
| **8** | Literal `FROM <upstream>` only in L1 + explicit allowlist | FG-065 upstream-consumed-once invariant |
| **9** | No `RUN` / `COPY` / `ADD` lines pulling from `docker.io` / `ghcr.io/library` | FG-066 forge-mirror-image invariant |
| **10** | `mirror/*` Dockerfiles use only `FROM` + `ARG` + `LABEL` + `COPY --from=<stage>` | FG-066 zero-mod mirror shape |
| **11** | No `images/source/` directory | FG-067 retired tier guard |
| **12** | Every L3 `base/*` has `FROM scratch` + ≥1 forge-internal consumer | FG-069 base-tier shape |
| **drift** | Exactly **6** literal `FROM <upstream>` lines across fleet | `verify-no-upstream-drift.sh _EXPECTED=6` (one per L1 pre-builder) |
| **source-inv** | Two-way sync between `_UPSTREAM_SOURCES` and in-tree references | `verify-source-inventory.py` (FG-068) |

---

## 7. Chain depth cap (FG-042 invariant)

**≤ 5 hops** from Docker Hub to any scratch runtime. Current ceilings:

| Family | Chain | Hops |
|---|---|---|
| Python | `debian:trixie-slim` → `python:3.14-slim-trixie` → `pre-builder/python-slim-trixie` → `builder/python-trixie` → `base/scratch-trixie` → scratch runtime | 5 |
| Go | `debian:trixie-slim` → `golang:1.27-trixie` → `pre-builder/go-slim-trixie` → `builder/go-trixie` → `base/scratch-trixie` → scratch runtime | 5 |
| Node | `debian:trixie-slim` → `node:24-trixie-slim` → `pre-builder/node-slim-trixie` → `builder/node-trixie` → dual-builder scratch | 4 |
| Zig | `debian:trixie-slim` → `pre-builder/debian-slim-trixie` → `pre-builder/zig-slim-trixie` → `builder/zig-trixie` → scratch runtime | 5 |

**Cost of adding a hop**: +~1 min of daily-cron time + an extra single-point-of-failure between the operator and the upstream distro. Every new tier or intermediate image deepens the chain for its downstream.

**Rule of thumb**: before adding a 6th tier, ask whether the new role can collapse into an existing tier. The four L2 builder siblings (python, go, node, zig) are justified by their distinct upstream toolchains — don't add `builder/rust-python-trixie`; add the Rust bits to an existing builder OR a new `builder/rust-trixie`.

---

## 8. Decision tree — adding a new image

Start at the top; the first "yes" determines the tier.

```
Is this a container image?
├── No  → it's L0.1 upstream source  (register in _UPSTREAM_SOURCES, consume via
│                                     git clone / curl in a builder stage)
└── Yes
    │
    Is it forge-signed + published under ghcr.io/bboortz/{mirror,pre-builder,
    builder,base}/ or a flat forge name?
    ├── No  → it's L0 upstream image  (not Forge's concern; consume via
    │                                   FROM <upstream> in L1 ONLY, or via
    │                                   COPY --from= in an L2 builder)
    └── Yes
        │
        Is the Dockerfile restricted to FROM + ARG + LABEL + COPY --from= only?
        ├── Yes → it's L0.5 mirror/<name>        (Rule 10 enforced)
        └── No
            │
            Does it FROM an upstream OS base AND only add apt-upgrade + CA +
            dumb-init?
            ├── Yes → it's L1 pre-builder/<name>  (Rule 8 enforced)
            └── No
                │
                Does it install dev tools (git, compilers, syft) that would be
                useless or dangerous in a production runtime?
                ├── Yes → it's L2 builder/<name>  (must have a sibling L1
                │                                   pre-builder; Rule 7 enforced)
                └── No
                    │
                    Does it FROM scratch (final stage) AND have ≥1 forge-internal
                    consumer?
                    ├── Yes → it's L3 base/<name>  (Rule 12 enforced)
                    └── No → it's L4 — flat path  (no prefix, no sub-tier)
```

**Naming convention inside each tier**: leaf names are concise; the tier prefix encodes the role, so don't duplicate it in the leaf. `base/scratch-trixie` not `base/scratch-base-trixie`. `builder/python-trixie` not `builder/forge-builder-python-trixie`. (Decisions O1 + O2 + O3 in the migration plan — do not reverse without an offsetting win.)

---

## 9. Enforcement surface

| Behavior | Tool | Hook |
|---|---|---|
| Tier membership / Dockerfile shape | `scripts/verify-dockerfile-conformance.py` | pre-commit (changed files) + `make test-fast` (full) |
| Upstream-FROM drift | `scripts/verify-no-upstream-drift.sh` | `make test-fast` |
| L0.1 source inventory sync | `scripts/verify-source-inventory.py` | `make test-fast` (FG-068) |
| Image dirs well-formed | `scripts/verify-image-dirs.py` | `make test-fast` |
| Image contracts (promises + expectations) | `scripts/verify-contracts.py` | `make test-fast` |
| CAP ↔ test traceability | `scripts/verify-traceability.sh` | `make test-fast` |
| Dep graph freshness | `make verify-dep-graph-fresh` | `make test-fast` |
| CI matrix discovery | `scripts/discover-images.sh {pre-builders,builders,base,mirrors,derivatives}` | GHA matrix emitter |

To add a new tier member, the only files that need editing:
- The image dir itself (`images/<tier>/<name>/`)
- The tier-member set in two places: `scripts/discover-images.sh` + `scripts/verify-dockerfile-conformance.py` + `scripts/image_from_graph.py` (grep for the existing tier's constant)
- `_UPSTREAM_SOURCES` in `scripts/_upstream_sources.py` if the image consumes a new L0.1 source
- `_EXPECTED` in `verify-no-upstream-drift.sh` only if the image adds a new L0 upstream anchor

---

## 10. Documented exceptions (allowlisted, not violations)

| Image | Tier | Deviation | Allowlist |
|---|---|---|---|
| `postgres-slim-trixie` | L4 | FROMs `postgres:18` directly (bypasses L1) | `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS` |
| `pre-builder/zig-slim-trixie` | L1 | FROMs `pre-builder/debian-slim-trixie` (intra-L1 edge; no Zig Docker Hub upstream) | `_INTRA_LAYER_EXEMPTIONS` |
| `base/python-trixie` | L3 | FROMs `base/scratch-trixie` (intra-L3 edge; overlay composes on substrate) | `_INTRA_LAYER_EXEMPTIONS` |
| `healthy-scratch-trixie` | L4 | COPYs `/hc` from external `ghcr.io/bboortz/hc:0.1.0` (forge-owned helper outside tier model) | `_UPSTREAM_HELPERS = ["hc"]` |
| `mirror/syft` | L0.5 | FROMs `anchore/syft:latest` (Docker Hub) | implicit — this is the mirror tier's purpose |

Every deviation is enumerated, CI-enforced, and justified. Zero free-form exceptions.

---

## 11. Public API vs internal implementation (FG-075)

Forge publishes two kinds of images. External consumers (homelab, Beaconry, future adopters) should FROM the **public API** only. The **internal implementation** is Forge build-time machinery — its paths may be refactored without notice.

### Public API (safe to FROM from outside Forge)

| Tier | Path | What consumers can rely on |
|---|---|---|
| **L3 `base/*`** | `ghcr.io/bboortz/base/<name>:<tag>` | Stable path. Daily-cron rebuilt. Cosign-signed. Dual-use: final runtime AND builder stage. Shape-agnostic — slim or scratch. |
| **L4 flat runtimes** | `ghcr.io/bboortz/<name>:<tag>` | Single-purpose application images (nginx, postgres, prometheus, …). Stable path. |
| **L0.5 `mirror/*`** | `ghcr.io/bboortz/mirror/<name>:<tag>` | Forge-signed zero-mod tool passthroughs. Safe via `COPY --from=` in consumer builder stages (e.g. `COPY --from=ghcr.io/bboortz/mirror/syft /syft /usr/local/bin/syft`). |

### Internal implementation (do NOT FROM from outside Forge)

| Tier | Path | Why internal |
|---|---|---|
| **L1 `pre-builder/*`** | `ghcr.io/bboortz/pre-builder/<name>:<tag>` | Build-time dedup target for L2 builders. Exists to enforce single-upstream-consumer rule (FG-042). Forge reserves the right to rename, re-shape, or restructure. External consumers who need a slim Python runtime should FROM `base/python-slim-trixie` instead. |
| **L2 `builder/*`** | `ghcr.io/bboortz/builder/<name>:<tag>` | Language-family toolchains for Forge's own from-source builds. Fat (400–900 MB), includes dev tools (`git`, compilers, `syft`). External consumers who need a Python builder stage should FROM `base/python-slim-trixie` (dual-use runtime + builder stage); for SBOM they `COPY --from=ghcr.io/bboortz/mirror/syft`. |

### Why the boundary matters

- **Decoupling from refactors**: FG-069 → FG-071 moved every internal tier to a new path (`scratch-base-trixie` → `base/scratch-trixie`; `forge-builder-python-trixie` → `builder/python-trixie`; …). Consumers that FROMed the OLD flat paths got stuck on frozen pre-migration digests. Keeping external consumers on `base/*` + flat L4 insulates them from future reorganization.
- **Supply-chain surface**: External consumers verify `ghcr.io/bboortz/<forge-image>` signatures bound to `.github/workflows/build.yml`. Keeping that verification contract narrow (base + flat L4 + mirror) reduces the surface Forge needs to keep stable.
- **Build efficiency**: L2 builders are 400–900 MB with dev tools consumers rarely need at runtime. `base/python-slim-trixie` (~75 MB) is dual-use — builder stage AND runtime — without carrying `git`/`make`/`g++`/`syft` into the consumer's runtime.

### Current public-API foundations

| Image | Role | Shape |
|---|---|---|
| `base/scratch-trixie` | Scratch overlay (glibc + CA + nss + /etc + zoneinfo) | overlay via `COPY --from=` |
| `base/python-scratch-trixie` | Python scratch foundation (3 forge consumers today: beaconry-*) | FROM scratch, overlay'd |
| `base/python-slim-trixie` | **NEW (FG-075)** — slim Python foundation; dual-use runtime + builder stage | FROM `pre-builder/python-slim-trixie` + /hc + nonroot + python3 entrypoint |

Future candidates (would land as separate FGs): `base/node-slim-trixie`, `base/node-scratch-trixie`. Go doesn't need a foundation — fully-static binaries FROM scratch suffice.

### Enforcement

No CI gate blocks external consumers from FROMing internal tiers — that's a consumer-side policy call. But:
- `scripts/verify-dockerfile-conformance.py` enforces internally that `pre-builder/*` + `builder/*` + `mirror/*` stay in their tier roles (Rules 7–10)
- `docs/LAYERING.md` + `README.md` document the boundary so new contributors + external adopters know which paths are stable
- Forge reserves the right to rebuild internal GHCR paths or re-point their `:latest` tag at any time

---

## 12. Historical references

- **Migration planning + decisions log**: `docs/plan/tier-layering-model.md` (FG-067 through FG-071)
- **Per-FG stories**: `docs/stories/FG-067-*.md` through `FG-071-*.md`
- **Capabilities delivered**: `docs/CAPABILITIES.md` — grep for `arch.*-tier-images`, `build.*-migrated`
- **Live dependency graph**: `docs/image-dependency-graph.md` + `docs/image-dependency-graph.svg`
