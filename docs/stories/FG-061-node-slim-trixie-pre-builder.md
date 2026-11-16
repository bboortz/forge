---
id: FG-061
slug: node-slim-trixie-pre-builder
status: ready
owner: bboortz
created: 2026-11-16
---

# FG-061 — `node-slim-trixie` pre-builder + migrate `uptime-kuma-slim-trixie` onto it

Forge's FG-042 single-upstream-consumer rule: every Docker Hub upstream anchor must be consumed by **exactly one** forge image. Today `node:24-trixie-slim` is consumed by two:

1. `forge-builder-node-trixie` — the builder-stage base (dedicated-toolchain exemption, same precedent as `forge-builder-go-trixie` FROMing `golang:1.27-trixie`).
2. `uptime-kuma-slim-trixie` — RUNTIME base (FG-045 shipped it this way; FG-048c kept it).

Point (2) is an informal exemption that would have tripped `verify-no-upstream-drift.sh` if that script tracked `node:24-trixie-slim`. It also blocks adding more Node-based images without compounding the drift.

FG-061 introduces `node-slim-trixie` as the forge-rooted Node runtime pre-builder (sibling of `debian-slim-trixie`, `python-slim-trixie`, `ubuntu-slim-noble`, `debian-slim-sid`), migrates `uptime-kuma-slim-trixie` runtime onto it, and clears the path for FG-062's `psitransfer-slim-trixie` (second consumer) without further infrastructure churn.

## 9 canonical answers

1. **Who** — Forge maintainer wanting to add a Node-based image; today each new one would have to rediscover whether to FROM upstream directly (growing the drift) or inline a pre-builder (not reusable). Also the FG-042 purity reviewer.

2. **When** — fires on every daily cron (new pre-builder publishes in the `publish-pre-builders` tier) and every PR touching Node-based images (now resolves `${NODE_SLIM_REF}` at build time instead of hardcoded upstream).

3. **What success looks like**:
   - `images/node-slim-trixie/` exists with the same shape as `debian-slim-trixie` (`FROM node:24-trixie-slim` + `apt-get upgrade` + `ca-certificates` + `dumb-init` + slim contract).
   - `scripts/discover-images.sh` `_PRE_BUILDERS` array includes `node-slim-trixie` (5 pre-builders now).
   - `scripts/verify-no-upstream-drift.sh` gains `node:24-trixie-slim` anchor, `_EXPECTED` 4 → **5** (accounts for the new pre-builder; `forge-builder-node-trixie` remains the second Dockerfile holding this anchor — dedicated-toolchain exemption, same shape as `forge-builder-go-trixie` with `golang:1.27-trixie`). **Actually two Dockerfiles hold the node anchor** (forge-builder-node + node-slim-trixie itself), so `_EXPECTED` += 1 becomes **_EXPECTED=5** (debian-slim-trixie, debian-slim-sid, python-slim-trixie, ubuntu-slim-noble, node-slim-trixie **and** forge-builder-node-trixie as its paired toolchain base — wait, that's 6).

     Resolution: `forge-builder-*-trixie` images are tracked as toolchain exemptions; the drift check treats `node:24-trixie-slim` with `_EXPECTED=2` (node-slim-trixie + forge-builder-node-trixie). Simplest implementation: make `_EXPECTED` per-anchor instead of a scalar. See plan doc for the array refactor.
   - `uptime-kuma-slim-trixie` Dockerfile's runtime stage FROMs `${NODE_SLIM_REF}` (default `ghcr.io/bboortz/node-slim-trixie:latest`) instead of `node:24-trixie-slim` directly.
   - All existing `uptime-kuma-slim-trixie` smokes pass post-migration (same JS runtime semantics — just a different upstream path).
   - `memory/docker-standard.md` chain-depth invariant rechecked: node-slim-trixie adds one hop for uptime-kuma's path; verify chain depth ≤ 5 still holds.

4. **Urgency** — infrastructure. Blocking FG-062 (psitransfer) cleanly. Not security-material.

5. **Happy path**:
   1. Branch `feat/FG-061-node-slim-trixie-pre-builder` from `dev`.
   2. Create `images/node-slim-trixie/` (Dockerfile + image.yaml + PROMISES.yaml + 6 smokes + scan-baseline + sid-pins/.gitkeep).
   3. Update `scripts/verify-no-upstream-drift.sh` to per-anchor `_EXPECTED` (array). `_EXPECTED` for `node:24-trixie-slim` = 2 (pre-builder + forge-builder-node-trixie toolchain base).
   4. Update `scripts/discover-images.sh` `_PRE_BUILDERS` array.
   5. Update `images/uptime-kuma-slim-trixie/Dockerfile`: add `ARG NODE_SLIM_REF=ghcr.io/bboortz/node-slim-trixie:latest`, replace `FROM ${NODE_BASE}` runtime with `FROM ${NODE_SLIM_REF}`. Keep the Node builder stage unchanged (already uses `forge-builder-node-trixie`).
   6. Update `scripts/build-image.sh` to resolve `NODE_SLIM_REF` (same pattern as `PYTHON_SLIM_REF` / `UBUNTU_SLIM_NOBLE_REF`).
   7. Update `docs/CAPABILITIES.md` — NEW `build.node-slim-base` CAP; EXT `build.pre-builder-tier`, `image.forge-rooted-slim-bases`.
   8. Update `memory/design-decisions.md` Node precedent if needed (no new policy — Node is already a dedicated-toolchain exception).
   9. Update `.github/workflows/build.yml` publish-pre-builders comment.
   10. Red acceptance test `test_FG_061_node-slim-trixie-pre-builder.sh` — 7 sections.
   11. `make check-smart-strict` green locally.
   12. PR → CI full-check → auto-merge.

6. **Edge cases / failure modes**:
   - **Chain depth**: `node:24-trixie-slim` → `node-slim-trixie` → `uptime-kuma-slim-trixie` = 3 hops. Under the cap of 5.
   - **Node version drift**: `node-slim-trixie` pins `node:24-trixie-slim`. When Node 26 LTS ships, decision point. Covered by FG-042 "one bump propagates atomically" pattern.
   - **uptime-kuma builder uses forge-builder-node-trixie while runtime uses node-slim-trixie**: different Node versions possible. Mitigation: both FROM `node:24-trixie-slim` upstream today, so same Node major. Explicitly documented in uptime-kuma Dockerfile comment.
   - **verify-no-upstream-drift refactor**: changing scalar `_EXPECTED` to per-anchor array needs careful test updating. FG-042's test asserts this invariant.

7. **Out of scope**:
   - **FG-062 psitransfer-slim-trixie** — follow-up FG that consumes this pre-builder.
   - **Promoting Node-based images to use SBOM syft from node-slim-trixie** — the forge-builder-node-trixie already has syft. Not needed in runtime.
   - **Node version bump to 26** — FG-062 (psitransfer upstream uses node:26) might trigger that, but FG-061 keeps node:24 (uptime-kuma's current base).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.node-slim-base` — Forge-rooted Node 24 runtime slim base.
   - EXT `build.pre-builder-tier` — publish-pre-builders matrix grows from 4 to 5.
   - EXT `image.forge-rooted-slim-bases` — Node family added.

## Gherkin acceptance

```
Scenario: node-slim-trixie is a valid Forge pre-builder
  Given current HEAD state
  When scripts/build-image.sh node-slim-trixie runs
  Then forge-local/node-slim-trixie:latest is built
  And its 6 smokes pass (is-node, has-shell, no-apt-cache, ca-bundle, apt-upgraded, size)
  And /usr/local/bin/node --version reports v24.x.x

Scenario: discover-images.sh pre-builders includes node-slim-trixie
  Given scripts/discover-images.sh pre-builders --filter all
  Then matrix output includes an entry for node-slim-trixie

Scenario: verify-no-upstream-drift tracks node:24-trixie-slim with _EXPECTED=2
  Given scripts/verify-no-upstream-drift.sh
  When it runs
  Then it passes
  And node:24-trixie-slim appears in _UPSTREAM_ANCHORS
  And the expected count for node:24-trixie-slim is 2 (pre-builder + forge-builder-node-trixie)

Scenario: uptime-kuma-slim-trixie runtime FROMs node-slim-trixie
  Given images/uptime-kuma-slim-trixie/Dockerfile at HEAD
  When grep for the runtime stage FROM line runs
  Then it references ${NODE_SLIM_REF} (default: ghcr.io/bboortz/node-slim-trixie:latest)
  And NOT node:24-trixie-slim directly

Scenario: uptime-kuma smokes still pass post-migration
  Given forge-local/uptime-kuma-slim-trixie:latest built from the new Dockerfile
  When the full smoke suite runs
  Then every smoke exits 0 (including smoke_ping_available.sh added in FG-055)

Scenario: build.yml publish-pre-builders tier includes node-slim-trixie
  Given .github/workflows/build.yml
  When comments naming the pre-builders are read
  Then node-slim-trixie appears alongside debian/python/ubuntu/debian-sid

Scenario: memory/docker-standard.md chain-depth example remains valid (≤ 5)
  Given the current deepest chain (debian:trixie-slim → ... → python-scratch-trixie)
  Adding node-slim-trixie does not extend any existing chain beyond 5 hops
```
