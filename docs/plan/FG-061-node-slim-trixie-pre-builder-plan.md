---
id: FG-061
slug: node-slim-trixie-pre-builder
story: ../stories/FG-061-node-slim-trixie-pre-builder.md
---

# FG-061 plan — `node-slim-trixie` pre-builder + migrate `uptime-kuma-slim-trixie`

Story: [FG-061](../stories/FG-061-node-slim-trixie-pre-builder.md).

## Design delta

`node:24-trixie-slim` is today referenced by **two** forge Dockerfiles:

- `forge-builder-node-trixie/Dockerfile` — `FROM ${NODE_BASE}` (ARG indirect; dedicated-toolchain exemption, same shape as `forge-builder-go-trixie`).
- `uptime-kuma-slim-trixie/Dockerfile` — `FROM ${NODE_BASE}` (RUNTIME base; informally exempted by FG-048c).

The runtime consumer is the one that breaks FG-042's "exactly one forge pre-builder per upstream anchor" invariant as soon as a second Node runtime image (FG-062 `psitransfer-slim-trixie`) is added. Fix: introduce `node-slim-trixie` as the forge-rooted Node runtime pre-builder, migrate `uptime-kuma-slim-trixie`'s runtime stage onto it, and declare `forge-builder-node-trixie` the single tolerated builder-stage exemption (same as `forge-builder-go-trixie` with `golang:1.27-trixie`).

Scalar `_EXPECTED` in `verify-no-upstream-drift.sh` continues to work: only LITERAL `^FROM node:24-trixie-slim` is counted by the grep. `forge-builder-node-trixie` uses `FROM ${NODE_BASE}` (ARG), which does NOT match the literal pattern — so `_EXPECTED` just bumps 4 → 5 for the five pre-builders (`debian-slim-trixie`, `debian-slim-sid`, `python-slim-trixie`, `ubuntu-slim-noble`, `node-slim-trixie`).

Chain depth after this change: `debian:trixie-slim` → `node:24-trixie-slim` (Docker Hub) → `node-slim-trixie` → `uptime-kuma-slim-trixie` = **3 hops**, well under the cap of 5.

## Alternatives rejected

- **Keep `uptime-kuma` FROMing `node:24-trixie-slim` directly, add a per-image exemption in `verify-no-upstream-drift.sh`.** Rejected: the whole point of FG-042 is to prevent "one more exemption every few FGs." FG-062 would add a second runtime → third exemption → unfixable drift.
- **Merge the runtime pre-builder into `forge-builder-node-trixie` (one image, both roles).** Rejected: builder + runtime are different contracts. Builder is big (git/curl/jq/make/g++/python3/syft), runtime is minimal (ca-certificates + dumb-init). Splitting keeps runtime size on-budget (× 1.1 of upstream `node:24-trixie-slim`).
- **Per-anchor `_EXPECTED` array refactor in `verify-no-upstream-drift.sh`.** Deferred: scalar continues to work because `forge-builder-node-trixie`'s `FROM ${NODE_BASE}` is ARG-indirect and doesn't match the literal grep. Refactor only worth doing when a second anchor needs ≠1 occurrences — not today.

## Edit catalogue

### 1. `images/node-slim-trixie/` (NEW, 11 files)

- `Dockerfile` — `FROM node:24-trixie-slim` + `apt-get upgrade` + install `ca-certificates dumb-init` + OCI labels. No shell removal — this is a slim pre-builder, not scratch.
- `image.yaml` — `tag: "latest"`, `platforms: [linux/amd64]`. No `depends_on` (upstream-rooted pre-builder).
- `PROMISES.yaml` — 8 promises: `runtime.node-binary`, `files.ca-certificates`, `files.dumb-init`, `apt.freshly-upgraded`, `apt.no-cache` (inverse), `presence.shell` → `image.has-shell` CAP, `shape.size-budget`, `scan.nonzero-accepted`. `spec_version: 1`, `version: "0.1"`.
- `scan-baseline.json` — initial empty critical_cves list.
- `sid-pins/.gitkeep` — placeholder.
- `tests/smoke_*.sh` × 7 — `smoke_node_version.sh`, `smoke_ca_bundle.sh`, `smoke_dumb_init.sh`, `smoke_apt_upgraded.sh`, `smoke_no_apt_cache.sh`, `smoke_has_shell.sh`, `smoke_size.sh`.

### 2. `scripts/verify-no-upstream-drift.sh`

Add `node:24-trixie-slim` to `_UPSTREAM_ANCHORS`; bump `_EXPECTED` 4 → 5; update error-message pre-builder enumeration.

### 3. `scripts/discover-images.sh`

Append `node-slim-trixie` to `_PRE_BUILDERS`.

### 4. `scripts/build-image.sh`

Four parallel edits mirroring the `UBUNTU_SLIM_NOBLE_REF` pattern:
- Auto-build dependency block (`grep -q NODE_SLIM_REF` + recursive invocation).
- Ref-resolution block (prefer `forge-local/node-slim-trixie:<tag>`, fall back to `ghcr.io/bboortz/...`).
- `forge-local/*` PULL_FLAG guard.
- `_HAS_LOCAL_DEP` check.
- `--build-arg NODE_SLIM_REF=...` in the buildx command.

### 5. `images/uptime-kuma-slim-trixie/Dockerfile`

- Add `ARG NODE_SLIM_REF=ghcr.io/bboortz/node-slim-trixie:latest`.
- Runtime stage: `FROM ${NODE_SLIM_REF}` (was: `FROM ${NODE_BASE}` resolving to `node:24-trixie-slim`).
- Drop `ca-certificates` + `dumb-init` from the `apt-get install` (baked by pre-builder). Keep `iputils-ping` (FG-055).

### 6. `.github/workflows/build.yml`

Update the `publish-pre-builders` tier comment to list 5 pre-builders.

### 7. `docs/CAPABILITIES.md`

- NEW `build.node-slim-base` — Forge-rooted Node 24 LTS runtime slim base.
- EXT `build.pre-builder-tier` — 5 members now.
- EXT `image.forge-rooted-slim-bases` — Node family added.

### 8. `docs/stories/INDEX.md`

Add FG-061 row.

### 9. `tests/acceptance/test_FG_061_node-slim-trixie-pre-builder.sh` (NEW)

7 sections encoding the Gherkin scenarios in the story.

## Merge order

1. Branch `feat/FG-061-node-slim-trixie-pre-builder` from `dev` (already current).
2. All edits in one commit (infrastructure plus the migration they enable — atomic).
3. Red test green locally: `make check-smart-strict`.
4. PR → CI full-check → auto-merge → release workflow → daily publish picks up both.

## Rollout

- `node-slim-trixie` publishes to GHCR for the first time in the `publish-pre-builders` tier of the next cron.
- `uptime-kuma-slim-trixie`'s next rebuild (also same cron) picks up `${NODE_SLIM_REF}` defaulting to the freshly-published `ghcr.io/bboortz/node-slim-trixie:latest` — same effective base as today, just one indirection added.

## Breaking changes

None. Consumer `cosign verify` commands unchanged. `uptime-kuma-slim-trixie`'s published digest changes (new base), but the public contract (`ENTRYPOINT`, `/hc`, port 3001, image.has-shell) is identical.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — pre-builder builds | Scenario 1 (build + 7 smokes + node -v) | ⏳ |
| Gherkin — discover | Scenario 2 (pre-builders matrix includes it) | ⏳ |
| Gherkin — drift gate | Scenario 3 (_EXPECTED=5 incl. new anchor) | ⏳ |
| Gherkin — uptime-kuma migration | Scenario 4 (FROM ${NODE_SLIM_REF}) | ⏳ |
| Gherkin — post-migration smokes | Scenario 5 (every smoke exits 0) | ⏳ |
| Gherkin — build.yml tier comment | Scenario 6 (5 pre-builders listed) | ⏳ |
| Gherkin — chain depth | Scenario 7 (≤ 5 hops) | ⏳ |
| Build/scan/verify symmetry | node-slim-trixie builds + scans + verifies | ⏳ |
| Self-consistency | CAP added + bidirectional links | ⏳ |
