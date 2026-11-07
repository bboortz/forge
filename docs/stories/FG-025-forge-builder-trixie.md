---
id: FG-025
slug: forge-builder-trixie
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-025 — Shared `forge-builder-trixie` image (Phase 1+2: all scratch images migrated)

Every Forge-native scratch image's builder stage duplicates the same ~30-60s of work: `apt-get update` + `apt-get upgrade` + install ca-certificates + install syft (for FG-020 SBOM). With FG-021 (buildx cache) + FG-023 (stamp-skip) landed, this still shows up in CI cold-cache runs and on the daily cron where every image rebuilds from scratch.

FG-025 publishes a new base image `ghcr.io/bboortz/forge-builder-trixie` that pre-bakes this common work, and migrates every Forge scratch image's builder stage to use it (scratch-base-trixie, python-scratch-trixie, nginx-scratch-trixie, postgres-scratch-trixie).

## 9 canonical answers

1. **Who** — Forge maintainer waiting on CI; daily-cron operator paying for apt-upgrade N times instead of once. Downstream consumers unaffected (new image is a BUILDER base, not a runtime consumer-facing one).

2. **When** — Any build of `scratch-base-trixie` (Phase 1). Phase 2 extends to the three scratch derivatives. Each daily cron rebuilds forge-builder-trixie first → every scratch image sees the fresh apt state.

3. **What success looks like** — forge-builder-trixie publishes as `ghcr.io/bboortz/forge-builder-trixie:0.1` and `:latest`. scratch-base-trixie's build is faster because it skips the apt+syft install (pre-done). Daily cron still gets fresh apt upgrades because forge-builder-trixie rebuilds nightly.

4. **Urgency** — Quality-of-life / cost. Not security-critical. Daily cron savings are the primary win; PR CI gains are modest (buildx cache already covers most of this).

5. **Happy path**:
   1. forge-builder-trixie publishes to GHCR via the new publish-builders CI tier.
   2. scratch-base-trixie's Dockerfile builder stage `FROM ghcr.io/bboortz/forge-builder-trixie:0.1`.
   3. scratch-base-trixie builds ~30s faster (apt+syft skipped).
   4. Downstream scratch derivatives still work unchanged (Phase 2 migrates them).

6. **Edge cases / failure modes**:
   - **Local dev with no network** — `FORGE_BUILDER_REF` falls back to `forge-local/forge-builder-trixie:0.1` after local pre-build.
   - **forge-builder-trixie not published yet on cold runner** — `publish-builders` publishes first; `publish-base` has `needs: [discover, publish-builders]`.
   - **Freshness lost** — forge-builder-trixie is rebuilt as part of the same daily cron; derivatives always FROM an up-to-date one.
   - **Phase 1 only migrates scratch-base** — the other 3 scratch derivatives still do their own apt+syft; future FG will migrate them.

7. **Out of scope**:
   - Migrating python-scratch / nginx-scratch / postgres-scratch builder stages (Phase 2)
   - Multi-arch (amd64 only; same as every other image)
   - Debian base other than trixie
   - Making forge-builder-trixie a consumer-facing product

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.shared-builder` — a published `forge-builder-trixie` image pre-loaded with apt-upgrade + CA certs + syft that scratch-image builder stages can FROM.
   - EXT `build.two-stage-scratch` — scratch-base-trixie's builder stage now uses forge-builder-trixie (Phase 1)
   - EXT `tooling.ci-build-cache` — new publish-builders tier in build.yml ensures correct cold-runner ordering

## Gherkin acceptance

```
Scenario: forge-builder-trixie is a complete image
  Given images/forge-builder-trixie/ exists
  When the image is built locally
  Then syft is on PATH at /usr/local/bin/syft
   And /etc/ssl/certs/ca-certificates.crt is present
   And /var/lib/apt/lists/ carries no Packages/Release files

Scenario: 3-tier CI publish orders forge-builder-trixie before scratch-base-trixie
  Given .github/workflows/build.yml is parsed
  When the discover job output is inspected
  Then builders, base, and derivatives matrices are all emitted
   And publish-builders runs before publish-base
   And publish-base has needs: [discover, publish-builders]

Scenario: scratch-base-trixie delegates builder-stage boilerplate
  Given images/scratch-base-trixie/Dockerfile
  When the builder stage is inspected
  Then it FROMs ${FORGE_BUILDER_REF} (defaulting to forge-builder-trixie)
   And it does NOT re-run apt-get upgrade
   And it does NOT install syft (pre-installed in forge-builder-trixie)

Scenario: build-image.sh pre-builds forge-builder-trixie for scratch images
  Given scripts/build-image.sh
  When invoked with a scratch image like scratch-base-trixie
  Then it first builds forge-builder-trixie if not in daemon
   And it passes --build-arg FORGE_BUILDER_REF=<local-tag>
```

## References

- Plan: `docs/plan/FG-025-forge-builder-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_025_forge-builder-trixie.sh`
- Capabilities: see `docs/CAPABILITIES.md`
