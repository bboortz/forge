---
id: FG-066
slug: forge-mirror-tier-syft
story: ../stories/FG-066-forge-syft-helper.md
---

# FG-066 plan — formalize `mirror/` tier + ship `mirror/syft`

Story: [FG-066](../stories/FG-066-forge-syft-helper.md).

## Design delta

Three threads land in one PR:

1. **New image tier `mirror/`** — nested directory convention `images/mirror/<name>/`; GHCR repo `ghcr.io/bboortz/mirror/<name>:<tag>`. First inhabitant: `mirror/syft` (zero-mod passthrough of `anchore/syft:latest`).
2. **New CI publish tier `publish-mirrors`** — runs in parallel with `publish-pre-builders` (no mutual dep); both block `publish-builders`.
3. **Rule 10 in verify-dockerfile-conformance.py** — enforces the mirror-tier zero-mod shape (allowed directives: `FROM`, `ARG`, `LABEL`, `COPY --from=`; everything else rejected).

After FG-066, zero forge-published image pulls anything from Docker Hub outside the 6 pre-builders. The `_HELPER_UPSTREAM_ALLOWLIST` is emptied.

## Alternatives rejected

- **Fold `mirror/syft` into `publish-pre-builders`**: wouldn't need a new tier, saves yaml. But conflates "forge-signed passthrough" with "forge-signed slim runtime" — the two shapes have different consumption patterns, different lint rules, different maintenance. Named-tier is cleaner.
- **Move `hc` under `mirror/hc`**: breaks 11 consumer Dockerfile defaults for no benefit. `hc` is forge-owned (not mirrored); stays at `ghcr.io/bboortz/hc`.
- **Create `mirror/postgres`**: zero consumers, regresses `postgres-slim-trixie`'s apt-upgrade CVE value. Kept as `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS` entry per FG-065.
- **Keep ARG + LABEL out of Rule 10's allowlist, inject OCI labels via build-image.sh `--label`**: workable but over-engineered. ARG + LABEL in the Dockerfile is readable + conventional; the invariant is "no content changes," not "no metadata declarations."

## Edit catalogue

### 1. `images/mirror/syft/` (NEW)

- `Dockerfile` — `FROM anchore/syft:latest` + `ARG GIT_SHA` + `ARG BUILD_TIMESTAMP` + 5 `LABEL` lines. Nothing else. Satisfies Rule 10.
- `image.yaml` — `tag: "latest"`, `repo: mirror/syft` (explicit; the yaml helper's default basename would collapse to `syft`), `platforms: [linux/amd64]`.
- `PROMISES.yaml` — 5 promises (`files.syft-binary`, `files.cyclonedx-cataloger`, `shape.zero-mod`, `shape.size-budget`, `scan.nonzero-accepted`).
- `scan-baseline.json` — initial empty critical_cves list.
- `sid-pins/.gitkeep`.
- `tests/smoke_syft_runs.sh`, `tests/smoke_syft_scan_cyclonedx.sh`, `tests/smoke_size.sh`.

### 2. `scripts/discover-images.sh` (EDIT)

- Bump find depth: `-maxdepth 1 -type d` → walk both `images/*/image.yaml` and `images/mirror/*/image.yaml` via `-maxdepth 2 -name image.yaml -printf '%h\n'`.
- New tier mode `mirrors` alongside `pre-builders` / `builders` / `base` / `derivatives`. Classification: any image whose path under `images/` starts with `mirror/` is a mirror. Nothing else is.
- Update `image_dir` output to carry the nested name (`mirror/syft` not `syft`) so build-image.sh + the matrix work consistently.

### 3. `scripts/build-image.sh` (EDIT)

- Add `SYFT_REF` resolution block mirroring `HC_REF` (first forge-local inspect, fallback to `ghcr.io/bboortz/mirror/syft:latest`).
- Add `--build-arg SYFT_REF="${SYFT_REF}"` to the buildx command.
- Add `SYFT_REF` to the `_HAS_LOCAL_DEP` check + `PULL_FLAG` guard (mirror of HC_REF handling).
- Add auto-build dependency: if the consumer's Dockerfile mentions `SYFT_REF`, recursively build `mirror/syft` first.
- IMAGE_DIR path handling: no change needed — `${ROOT}/images/${IMAGE_DIR}` already works for nested paths when IMAGE_DIR is `mirror/syft`.

### 4. `scripts/verify-dockerfile-conformance.py` (EDIT)

- Remove `_HELPER_UPSTREAM_ALLOWLIST` content (syft was the only entry); keep the empty set as a deprecated placeholder with a comment pointing at `_FORGE_MIRRORS`.
- Add `_FORGE_MIRRORS = {"mirror/syft"}` set. Grows per-FG when new mirrors land.
- Add `SYFT_REF` to `_KNOWN_REF_ARGS`.
- Classify `mirror/*` paths: `_tier_of("mirror/syft")` → `"mirror"` (new).
- Rule 10 (NEW): for any Dockerfile under `images/mirror/*/Dockerfile`, every line must be in the mirror-tier allowlist (`FROM`, `ARG`, `LABEL`, `COPY --from=`). Any `RUN`/`ENV`/`WORKDIR`/`CMD`/`USER`/`ADD`/`EXPOSE`/`HEALTHCHECK`/`VOLUME`/`SHELL`/`STOPSIGNAL`/`ONBUILD` fails the lint with the actionable message "arch.forge-mirror-image invariant — mirrors are zero-mod passthroughs; use a pre-builder tier instead if you need to add behavior."
- Rule 8 (EXISTING) — ensure literal `^FROM anchore/syft:latest` IS allowed in `images/mirror/syft/Dockerfile` (the mirror ITSELF must FROM upstream — that's the whole point). Add a mirror-exemption clause to Rule 8.

### 5. `scripts/image_from_graph.py` (EDIT)

- Add `_FORGE_MIRRORS = ["mirror/syft"]` list.
- Classify `mirror/*` via `_tier_of()` → new `"L0_5"` tier.
- Update `all_images()` to walk 2 levels deep + resolve nested image.yaml paths.
- Mermaid emitter: add new subgraph `L0_5_mirrors "Forge mirrors (zero-mod upstream passthroughs)"` between `L0_upstream` and `L1_prebuilders`.
- Add `UP_ANCHORE_SYFT` upstream node (if not already present via helper-upstream classification). Actually the helper-upstream path already catches it — rename/relocate to live under the mirrors-feeding row.
- Styling: new `classDef mirror` with a distinct color (e.g. teal) — keep upstream gray, prebuilder orange, builder blue, baseline green, slim white, scratch yellow, external purple.

### 6. `images/forge-builder-{python,go,node}-trixie/Dockerfile` (EDIT)

- `ARG SYFT_SRC=docker.io/anchore/syft:latest` → `ARG SYFT_REF=ghcr.io/bboortz/mirror/syft:latest`.
- `FROM ${SYFT_SRC} AS syft-src` → `FROM ${SYFT_REF} AS syft-src`.
- Nothing else in the Dockerfile body changes.

### 7. `images/forge-builder-{python,go,node}-trixie/image.yaml` (EDIT)

- Append `  - mirror/syft` to each `depends_on:` list (python's is new; go + node already have their `-slim-trixie` dep from FG-065).

### 8. `images/forge-builder-{python,go,node}-trixie/EXPECTATIONS.yaml` (EDIT)

- Add a new `- image: syft` block (image name per the PROMISES.yaml top-level `image:` field) with `files.syft-binary` expectation + preflight pointer.

### 9. `.github/workflows/build.yml` (EDIT)

- Add new job `publish-mirrors` (sibling of `publish-pre-builders`, same template, matrix from `discover-images.sh mirrors`).
- Update `publish-builders`'s `needs:` from `[discover, publish-pre-builders]` → `[discover, publish-pre-builders, publish-mirrors]`. Same `if: !cancelled() && …` guard logic.
- Update the top-of-file comment to describe the now-5-tier ordering.

### 10. `docs/CAPABILITIES.md` (EDIT)

- NEW `arch.forge-mirror-image` — the invariant.
- NEW `build.mirror-tier` — the new CI tier.
- NEW `build.mirror-syft` — the first member.
- EXT `build.pre-builder-tier` — notes the companion mirror-tier.
- EXT `build.shared-{python,go,node}-builder` — all three now source syft from forge mirror.

### 11. `docs/stories/INDEX.md` (EDIT)

- Add FG-066 row.

### 12. `memory/design-decisions.md` (EDIT)

- Add new section "Forge mirror tier" describing the pattern + the zero-mod rule.

### 13. `memory/supply-chain.md` (EDIT)

- Note syft is now forge-signed via mirror/syft — no more Docker Hub pulls for syft.

### 14. `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh` (NEW)

9+ sections encoding the Gherkin scenarios.

### 15. Auto-regenerated

- `docs/image-dependency-graph.md` + `.svg` — regenerated via `make dep-graph`. Expected: new `mirror/syft` node in L0.5 subgraph; dashed edges to all 3 forge-builders.

## Merge order

1. Branch from `dev`.
2. Scaffold `images/mirror/syft/` first (no dependency on scripts).
3. Update scripts (`discover-images.sh`, `verify-dockerfile-conformance.py`, `image_from_graph.py`, `build-image.sh`) — the lint will start failing on the 3 forge-builders' SYFT_SRC → SYFT_REF mismatch until step 4.
4. Flip the 3 forge-builder Dockerfiles + image.yaml + EXPECTATIONS.
5. Update `.github/workflows/build.yml` + CAPABILITIES + INDEX + memory.
6. Write red test; run locally.
7. Local build sweep: mirror/syft → 3 forge-builders → downstream Go/Node/Python-source smoke sanity.
8. Regenerate scan-baseline.json for mirror/syft.
9. `make dep-graph` → regen committed.
10. `make check-smart-strict` green locally.
11. PR → CI full-check → auto-merge → release → next cron re-publishes.

## Rollout

- Zero consumer-side impact. No `cosign verify` command changes. Downstream Go/Node/Python-source images use `${FORGE_BUILDER_*_REF}` — unchanged.
- First publish: `mirror/syft` lands as a new GHCR repo under `ghcr.io/bboortz/mirror/syft`. All three forge-builders' next publish picks up the new FROM.
- One-time cache miss on the 3 forge-builders' first layer after FROM change; apt layer stays.

## Breaking changes

None for consumers. Internal: the `SYFT_SRC` ARG name is retired (replaced by `SYFT_REF`) — anyone passing `--build-arg SYFT_SRC=...` externally would lose the override, but this is not a public contract.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — mirror/syft layout | Scenario 1 | ⏳ |
| Gherkin — Rule 10 enforced | Scenario 2 | ⏳ |
| Gherkin — 3 FBs source from mirror | Scenario 3 | ⏳ |
| Gherkin — _HELPER_UPSTREAM_ALLOWLIST empty | Scenario 4 | ⏳ |
| Gherkin — dep graph L0.5 subgraph | Scenario 5 | ⏳ |
| Gherkin — upstream drift still green | Scenario 6 | ⏳ |
| Gherkin — discover-images mirrors mode | Scenario 7 | ⏳ |
| Gherkin — build.yml publish-mirrors tier | Scenario 8 | ⏳ |
| Gherkin — hc stays put | Scenario 9 | ⏳ |
| Gherkin — downstream rebuilds green | Scenario 10 | ⏳ |
| Build/scan/verify symmetry | mirror/syft + 3 FBs build + scan clean | ⏳ |
| Self-consistency | 3 new CAPs + 4 EXT; bidirectional links | ⏳ |
| No consumer-contract break | zero verify-command or consumer-Dockerfile changes | ✅ |
