---
id: FG-066
slug: forge-mirror-tier-syft
status: draft
owner: bboortz
created: 2026-11-17
---

# FG-066 — Formalize `mirror/` tier for forge-signed zero-mod passthroughs; first inhabitant `mirror/syft`

Today the three forge-builders (`forge-builder-python-trixie`, `forge-builder-go-trixie`, `forge-builder-node-trixie`) pull syft directly from Docker Hub in a builder stage:

```dockerfile
ARG SYFT_SRC=docker.io/anchore/syft:latest
FROM ${SYFT_SRC} AS syft-src
...
COPY --from=syft-src /syft /usr/local/bin/syft
```

This is the **last remaining Docker Hub consumption in any Forge builder** after FG-065 retired the dedicated-toolchain exemption. The `_HELPER_UPSTREAM_ALLOWLIST` in `scripts/verify-dockerfile-conformance.py` exists exclusively for syft.

FG-066 does three things in one PR:

1. **Formalize `mirror/` as a new image tier AND a dedicated CI publish stage** — a named category of forge-signed, structurally-zero-change passthroughs of external tool images. Directory convention `images/mirror/<name>/`, GHCR repo `ghcr.io/bboortz/mirror/<name>:<tag>`. New CI tier `publish-mirrors` runs in parallel with `publish-pre-builders` (both have no mutual dependency; both block `publish-builders`). Members today: none; after FG-066: `mirror/syft`. Future: `mirror/grype`, `mirror/hadolint`, `mirror/terraform`, etc. — each lands as ~30 lines.

2. **Publish `mirror/syft`** as the first inhabitant — a zero-mod forge-signed mirror of `anchore/syft:<tag>`. All three forge-builders flip from `FROM docker.io/anchore/syft:latest` to `FROM ghcr.io/bboortz/mirror/syft:<tag>`. Removes the last Docker Hub pull from any forge builder.

3. **New lint rule + dep-graph tier** — `verify-dockerfile-conformance.py` Rule 10 enforces mirror zero-mod shape; FG-064's dep-graph emitter gains an `L0_5_mirrors` subgraph between L0 upstream and L1 pre-builders.

After FG-066, zero forge-published image pulls anything from Docker Hub outside the 6 pre-builders. The last exemption pocket in the conformance lint (`_HELPER_UPSTREAM_ALLOWLIST`) is retired, and the publish pipeline grows from 4 tiers to 5.

## Scope boundaries — what belongs under `mirror/` and what doesn't

**In** (FG-066 ship):
- `mirror/syft` — pure passthrough of `anchore/syft`.

**In** (future, same pattern — one FG each):
- `mirror/grype` — anchore's CVE scanner (currently pulled fresh per scan).
- `mirror/hadolint`, `mirror/terraform`, `mirror/shellcheck` — currently pulled during `github-runner-noble` build.
- `mirror/cosign-cli` — if we ever want operator-side cosign verify shipped with a forge-signed binary.

**NOT a mirror** (retained at existing paths):
- `hc` — forge's OWN binary (sourced from `bboortz/hc`, not external). Stays at `ghcr.io/bboortz/hc:<ver>`. The `mirror/` category is reserved for re-wrapping EXTERNAL upstream images; publishing our own binaries doesn't fit the semantics.
- `postgres-slim-trixie` — externally-maintained runtime but **adds `apt-upgrade` on top** (real CVE-fix value). A `mirror/postgres` zero-mod version would regress that + have zero consumers. Stays in `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS` per FG-065.
- The 6 pre-builders (`<lang>-slim-trixie`, `debian-slim-{sid,trixie}`, `ubuntu-slim-noble`) — all add `apt-upgrade` + `ca-certificates` + `dumb-init` on top of their upstream base. Not zero-mod; they're pre-builders, not mirrors.

## "Zero changes" — what the rule means + lint enforcement

`mirror/<name>/Dockerfile` is restricted to:

1. Exactly one or two `FROM` stages: (a) `FROM <upstream>` as a source stage, then (b) optional `FROM scratch` runtime with a single `COPY --from=src ...` to copy the binary/artifacts forward. For single-binary tools (syft), both stages are allowed. For images already in `FROM scratch` shape upstream (anchore/syft is), either shape works.
2. `LABEL` directives (OCI metadata only — source, revision, created, licenses).
3. `ENTRYPOINT` ONLY if it re-states upstream's; prefer inherited.
4. **Forbidden**: `RUN`, `ENV` (other than labels), `WORKDIR`, `CMD`, `USER`, `ADD`, `COPY` of anything the operator defined, `APT`/`RUN apt-*`, `EXPOSE` beyond upstream.

Enforced by `scripts/verify-dockerfile-conformance.py` **Rule 10 (NEW)**: for any Dockerfile under `images/mirror/*/Dockerfile`, parse line-by-line and reject any directive outside the allowed set. Actionable failure messages name the offending line + the mirror-policy rule.

This keeps `mirror/<name>:*` behaviorally identical to its upstream — a forge-rooted re-publish, not a modified derivative. The only differences from upstream: forge OCI labels + cosign signature over the forge-built digest.

## 9 canonical answers

1. **Who** — Forge maintainer tightening the supply-chain surface area (one fewer upstream dependency per build); daily-cron operator (one fewer Docker Hub rate-limit hit per build); Beaconry / external auditor (one fewer unsigned-by-forge binary in every SBOM-generation path); future maintainer wanting to add `mirror/hadolint` etc. with a clear pre-existing pattern + a dedicated CI tier to land in.

2. **When** — Daily cron: new `publish-mirrors` CI tier runs **in parallel with** `publish-pre-builders` (no mutual dependency). Both block `publish-builders`, so forge-builder-{python,go,node}-trixie now `needs: [discover, publish-mirrors, publish-pre-builders]`. Rest of the tier chain unchanged. Parallel scheduling keeps wall-clock impact minimal (~2 min per tier; they overlap).

3. **What success looks like**:
   - `images/mirror/syft/` exists with the mirror-tier shape: Dockerfile is a 2-stage trivial passthrough (`FROM anchore/syft:<tag> AS src` + `FROM scratch` + `COPY --from=src /syft /syft` + OCI labels). No `RUN`, no apt, no ENV.
   - `images/mirror/syft/image.yaml`: `tag` matches the anchore release (pinned to specific version OR tracks `latest` via FG-050 `build.ref-latest-release` — see plan doc choice).
   - `images/mirror/syft/PROMISES.yaml`: declares `files.syft-binary` (CycloneDX cataloger present + `syft version` runs).
   - All three forge-builders Dockerfiles flip: `ARG SYFT_SRC=docker.io/anchore/syft:latest` → `ARG SYFT_REF=ghcr.io/bboortz/mirror/syft:<tag>`; `FROM ${SYFT_SRC}` → `FROM ${SYFT_REF}`.
   - All three `image.yaml` depends_on grows `syft` (via nested `mirror/syft` path — dep resolver already supports nested names).
   - `scripts/verify-dockerfile-conformance.py` changes: `_HELPER_UPSTREAM_ALLOWLIST` emptied (no longer needed); `_KNOWN_REF_ARGS` gains `SYFT_REF`; `_FORGE_MIRRORS` set added for Rule 6 tier classification; **Rule 10** added to enforce mirror-tier zero-changes contract.
   - `scripts/discover-images.sh` — `find` depth bumped from `-maxdepth 1` to `-maxdepth 2 -name image.yaml -printf '%h\n'` so nested `mirror/*` dirs are discovered. **New tier mode `mirrors`** added alongside `pre-builders` / `builders` / `base` / `derivatives`. Classification: any image under `images/mirror/*/` is a mirror; nothing else is.
   - `docs/CAPABILITIES.md`: NEW `arch.forge-mirror-image` (the invariant); NEW `build.mirror-tier` (new CI tier); NEW `build.mirror-syft` (the first member); EXT `build.pre-builder-tier` (noting the companion mirror-tier); EXT `build.shared-{go,node,python}-builder` (now sources syft via forge mirror).
   - `.github/workflows/build.yml` gains **new `publish-mirrors` job** (sibling of `publish-pre-builders`, both parallel; both block `publish-builders`). Matrix populated from `scripts/discover-images.sh mirrors`.
   - FG-064 dep graph regenerated: new `mirror/syft` node in a new **L0.5 "Forge mirrors"** subgraph between L0 Upstream and L1 Pre-builders; solid edge `anchore/syft → mirror/syft`; dashed `mirror/syft -.-> forge-builder-{python,go,node}-trixie`.
   - `_UPSTREAM_HELPERS` set in `image_from_graph.py` stays as `{"hc"}` (hc isn't a mirror). The new `_FORGE_MIRRORS` tier is separate.
   - Zero regression in any downstream Go/Node/Python-source image: all 7 current forge-builder consumers rebuild green.

4. **Urgency** — Infrastructure quality-of-life + supply-chain tightening. Not security-critical today. Nice-to-have. One-day scope.

5. **Happy path**:
   1. Branch `feat/FG-066-forge-mirror-tier-syft` from `dev`.
   2. Create `images/mirror/syft/` (Dockerfile + image.yaml + PROMISES.yaml + 3 smokes + scan-baseline + sid-pins/.gitkeep).
   3. Pick version tracking: pin to `anchore/syft:v1.57.0` (reproducible) OR float `latest` via FG-050 pattern (auto-tracking). Recommended: FG-050 pattern, matching uptime-kuma / cadvisor / etc.
   4. Update `scripts/discover-images.sh` to walk 2 levels deep + filter by `image.yaml` presence.
   5. Update `scripts/verify-dockerfile-conformance.py`: remove helpers allowlist for syft; add `SYFT_REF` to `_KNOWN_REF_ARGS`; add `_FORGE_MIRRORS` set; implement Rule 10 (mirror-tier zero-changes enforcement).
   6. Update `scripts/image_from_graph.py`: `_FORGE_MIRRORS` list + new "L0.5 Forge mirrors" subgraph in the mermaid emitter.
   7. Update `scripts/build-image.sh`: `SYFT_REF` auto-build-dependency (mirror of HC_REF) + ref-resolution + `--build-arg SYFT_REF` wiring. Handle the nested `images/mirror/*` paths.
   8. Flip all three forge-builder Dockerfiles (ARG + FROM swap).
   9. Add `depends_on: [mirror/syft]` or `[syft]` (resolver path — see plan doc for canonical form) to all three forge-builders' `image.yaml`.
   10. Update each forge-builder's `EXPECTATIONS.yaml` with a new `files.syft-binary` expectation pointing at `mirror/syft`'s PROMISES.
   11. Update `.github/workflows/build.yml`: add new `publish-mirrors` job (sibling of `publish-pre-builders`, both parallel, no mutual dep). Add both to `publish-builders`'s `needs:` clause. Update the top-of-file comment to describe the now-5-tier publish ordering (mirrors + pre-builders → builders → base → derivatives).
   12. Update `docs/CAPABILITIES.md`: NEW `arch.forge-mirror-image` (invariant); NEW `build.mirror-syft`; EXT `build.shared-*-builder`.
   13. Update `docs/stories/INDEX.md` — FG-066 row.
   14. Update `memory/supply-chain.md` + `memory/design-decisions.md` — note syft is now forge-signed via the mirror tier; `_UPSTREAM_HELPERS` set is emptied.
   15. Red acceptance test `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh` (9 sections).
   16. Local full-build sweep: `mirror/syft` → all three forge-builders → every downstream consumer. All smokes green.
   17. `make dep-graph` regenerates; new tier visible in L0.5.
   18. PR → CI full-check → auto-merge → release → publish.

6. **Edge cases / failure modes**:
   - **`ghcr.io/bboortz/mirror/syft` nested path**: GHCR supports `/`-delimited repo paths. Cosign `--certificate-identity` continues working the same way. Docker/buildx pull / push paths tested in the acceptance test.
   - **syft version drift**: FG-050 `build.ref-latest-release` resolution + daily cron keeps us within 24h. Pin-and-bump alternative is more reproducible but needs manual bumps when a syft CVE drops.
   - **`anchore/syft:latest` vs pinned tag**: anchore maintains both. Prefer FG-050 auto-resolution, baked into `org.opencontainers.image.revision`.
   - **syft's own CVE surface**: syft is ~70MB static Go binary. grype scan reports Go stdlib + vendored dep CVEs. Appears in `mirror/syft`'s scan-baseline.json; no runtime impact (syft runs at build time only).
   - **Chain depth**: mirror/ is a pure COPY-from helper (no FROM chain contribution). Unchanged.
   - **Circular dependency**: `mirror/syft` doesn't need any forge builder (no compile step, just FROM + COPY). No circularity.
   - **If anchore stops publishing**: forge-signed mirror continues to carry the last-pulled version indefinitely — one more buffer against upstream disruption.
   - **Dev-loop (`forge-local/`)**: `scripts/build-image.sh` handles the forge-local fallback for SYFT_REF same as HC_REF today. First local build of a forge-builder triggers `mirror/syft` build.
   - **Rule 10 lint scope creep**: Rule 10 is strict (no RUN, no ENV, etc.). If a future mirror genuinely needs e.g. a `USER` directive (uncommon), the lint is a blocker — either relax Rule 10's allowlist OR declare the image is NOT a mirror and move it to a different tier.
   - **`hc` stays put at `ghcr.io/bboortz/hc`**: consumer Dockerfiles (`HC_REF` ARG default) are unchanged. `hc` is forge's own binary, not a mirror of an external.

7. **Out of scope**:
   - **Shipping other mirror candidates** (`mirror/grype`, `mirror/hadolint`, `mirror/terraform`, `mirror/cosign-cli`) — each is a 30-line follow-up FG that reuses this story's pattern.
   - **Moving `hc` to `mirror/hc`** — different semantics (forge-owned binary, not an external mirror). Could revisit if the invariant evolves to "forge-signed passthrough of ANY source" semantically.
   - **Creating `mirror/postgres`** — zero consumers + regresses `postgres-slim-trixie`'s apt-upgrade value. Covered separately by `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS`.
   - **Running syft at runtime** (currently build-time only): out of scope.
   - **Changing syft's SBOM format** or output: still CycloneDX JSON (FG-001 convention).

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `arch.forge-mirror-image` — architectural invariant: `images/mirror/<name>/` is a reserved directory for forge-signed zero-mod passthroughs of external upstream tool images. Dockerfile content restricted to `FROM`, `LABEL`, optional `COPY --from=src` of the artifact; no `RUN`/`APT`/`ENV`/`WORKDIR`/`CMD`/`USER`. GHCR repo is `ghcr.io/bboortz/mirror/<name>:<tag>`. Enforced by `scripts/verify-dockerfile-conformance.py` **Rule 10**. First member: `mirror/syft` (FG-066). Future members (`mirror/grype`, `mirror/hadolint`, etc.) land per-case.
   - NEW `build.mirror-tier` — dedicated CI publish tier `publish-mirrors` running in parallel with `publish-pre-builders`. Both have no mutual dependency; both block `publish-builders`. The 4-tier publish ordering from FG-042/FG-061/FG-065 grows to **5 tiers**: `{publish-mirrors ∥ publish-pre-builders}` → `publish-builders` → `publish-base` → `publish-derivatives`.
   - NEW `build.mirror-syft` — forge-signed mirror of `anchore/syft`. Consumed via `COPY --from=` by all three forge-builders. Replaces the `_HELPER_UPSTREAM_ALLOWLIST` exemption that previously allowed `anchore/syft:latest` as a literal upstream FROM.
   - EXT `build.pre-builder-tier` — runs in parallel with the new `build.mirror-tier` (sibling, not blocker).
   - EXT `build.shared-python-builder` — now sources syft via forge mirror instead of Docker Hub.
   - EXT `build.shared-go-builder` — same.
   - EXT `build.shared-node-builder` — same.
   - EXT `image.forge-rooted-slim-bases` / `supply-chain.single-pre-builder-per-upstream` — the last Docker Hub helper is now mirrored through forge.

## Gherkin acceptance

```
Scenario: images/mirror/syft/ exists as a pure passthrough
  Given current HEAD
  Then images/mirror/syft/Dockerfile, image.yaml, PROMISES.yaml,
       scan-baseline.json all exist
  And the Dockerfile contains only FROM + LABEL + COPY --from=src directives
  And the Dockerfile has no RUN, no ENV (other than labels), no WORKDIR,
       no CMD, no USER, no APT

Scenario: Rule 10 catches a mirror attempting to add behavior
  Given a synthetic images/mirror/foo/Dockerfile that contains `RUN echo x`
  When scripts/verify-dockerfile-conformance.py runs
  Then it fails with
      "images/mirror/foo/Dockerfile:N: 'RUN' is not allowed in a mirror
       image (arch.forge-mirror-image invariant — mirrors are zero-mod
       passthroughs; use a pre-builder tier instead if you need to add
       behavior)"

Scenario: all three forge-builders source syft from mirror/syft
  Given images/forge-builder-{python,go,node}-trixie/Dockerfile at HEAD
  Then each declares `ARG SYFT_REF=ghcr.io/bboortz/mirror/syft:<tag>`
  And each has `FROM ${SYFT_REF} AS syft-src`
  And none reference `docker.io/anchore/syft` or `anchore/syft:latest`
      in any FROM line

Scenario: _HELPER_UPSTREAM_ALLOWLIST is emptied
  Given scripts/verify-dockerfile-conformance.py at HEAD
  Then _HELPER_UPSTREAM_ALLOWLIST is an empty set
       (no helper upstreams remain after FG-066)
  And the file documents `_FORGE_MIRRORS` as the replacement concept

Scenario: dep graph shows the new mirror tier
  Given docs/image-dependency-graph.md regenerated via `make dep-graph`
  Then a new subgraph L0_5_mirrors "Forge mirrors (zero-mod upstream passthroughs)"
       exists between L0_upstream and L1_prebuilders
  And mirror/syft is a member of L0_5_mirrors
  And the mermaid block contains:
      `anchore/syft:<tag> → mirror/syft` (solid, upstream → mirror)
      `mirror/syft -.-> forge-builder-python-trixie` (dashed, COPY --from)
      `mirror/syft -.-> forge-builder-go-trixie`
      `mirror/syft -.-> forge-builder-node-trixie`
  And it does NOT contain:
      `anchore/syft → forge-builder-*` direct edges

Scenario: verify-no-upstream-drift stays at _EXPECTED=6
  Given scripts/verify-no-upstream-drift.sh
  Then the guard exits 0
  And `_EXPECTED` stays 6 (unchanged — mirror/syft's upstream FROM is a
      new literal match, but anchore/syft isn't in _UPSTREAM_ANCHORS and
      shouldn't be — those anchors are language-family bases, not tools)

Scenario: discover-images.sh walks nested mirror/ paths + exposes new `mirrors` mode
  Given scripts/discover-images.sh
  When it runs with tier=mirrors
  Then its output includes exactly one entry: `mirror/syft`
  When it runs with tier=pre-builders
  Then its output includes the 6 existing pre-builders and NOT `mirror/syft`
  When it runs with tier=all
  Then its output includes `mirror/syft` as a discovered image dir

Scenario: build.yml grows a publish-mirrors tier parallel to publish-pre-builders
  Given .github/workflows/build.yml at HEAD
  Then a job `publish-mirrors` exists
  And its matrix comes from `discover-images.sh mirrors`
  And `publish-builders` has `needs: [discover, publish-mirrors, publish-pre-builders]`
      (or a semantically equivalent OR-of-sibling-tier gate)
  And `publish-mirrors` has no needs: on publish-pre-builders (parallel)
  And `publish-pre-builders` has no needs: on publish-mirrors (parallel)

Scenario: hc stays at ghcr.io/bboortz/hc (NOT moved to mirror/hc)
  Given images/hc does NOT exist and images/mirror/hc does NOT exist
  And every consumer's Dockerfile declares `ARG HC_REF=ghcr.io/bboortz/hc:<tag>`
  Then FG-066 makes NO changes to hc's path or any consumer

Scenario: every downstream Go/Node/Python-source image still builds green
  Given forge-local/forge-builder-{python,go,node}-trixie:latest built
        against forge-local/mirror/syft:latest
  When every downstream (cadvisor, node-exporter, prometheus, alertmanager,
        ipmi-exporter-*, postgres-slim-gosu-builder, uptime-kuma,
        + every Python scratch runtime) is rebuilt
  Then every image builds successfully
  And `syft version` output inside every forge-builder matches the
      version baked into mirror/syft
```

## References

- Plan: `docs/plan/FG-066-forge-mirror-tier-syft-plan.md` (follow-up)
- Red test: `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh` (follow-up)
- Pattern precedent: `ghcr.io/bboortz/hc` (static-binary helper consumed via `COPY --from=` — stays at its current path, NOT moved under `mirror/`)
- Capabilities touched: `build.shared-python-builder` (FG-025), `build.shared-go-builder` (FG-046), `build.shared-node-builder` (FG-048), new `arch.forge-mirror-image` invariant
- Follow-up mirror candidates: `mirror/grype`, `mirror/hadolint`, `mirror/terraform`, `mirror/shellcheck`, `mirror/cosign-cli` — each a 30-line FG reusing this story's pattern.
