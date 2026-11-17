---
id: FG-065
slug: forge-builder-dogfood-symmetry
story: ../stories/FG-065-forge-builder-dogfood-symmetry.md
---

# FG-065 plan — language-family image-pair invariant + Go pre-builder + both forge-builders dogfood

Story: [FG-065](../stories/FG-065-forge-builder-dogfood-symmetry.md).

## Design delta

Two Dockerfile swaps + one new pre-builder image + one new architectural invariant (lint-enforced). No consumer edits.

- New `images/go-slim-trixie/` — standard pre-builder (FROM `golang:1.27-trixie` + apt-upgrade + ca-certificates + dumb-init). Mirrors FG-061's `node-slim-trixie` shape exactly.
- `forge-builder-go-trixie/Dockerfile` — `ARG GO_BASE=golang:1.27-trixie` → `ARG GO_SLIM_REF=ghcr.io/bboortz/go-slim-trixie:latest`; `FROM ${GO_BASE}` → `FROM ${GO_SLIM_REF}`.
- `forge-builder-node-trixie/Dockerfile` — same shape: `ARG NODE_BASE` → `ARG NODE_SLIM_REF`; FROM swap.
- Both `image.yaml` files grow `depends_on: [<lang>-slim-trixie]`.
- `scripts/verify-dockerfile-conformance.py` gains a new rule: every `images/forge-builder-<lang>-trixie/` has a sibling `images/<lang>-slim-trixie/`. Encodes the new `arch.language-family-image-pair` invariant so future language families (Rust, Zig, Ruby, Java, …) can't land half-paired.
- `memory/design-decisions.md` + `memory/docker-standard.md` — retire the "dedicated-toolchain exemption" callout; replace with the "Language family image pairs" invariant.

## Alternatives rejected

- **Skip go-slim-trixie — keep Go as the only remaining exemption**. Rejected: user's architectural rule is explicit ("every language has a pair"). Also, half-closed exemption is harder to defend to future reviewers than either full coverage or an explicit "Go only" carve-out.
- **Create `go-slim-trixie` without flipping FBG** (pre-builder exists but unused). Rejected: pure dead infrastructure (same anti-pattern as debian-slim-sid). Only makes sense if FBG dogfoods it.
- **Flip FBN without creating go-slim-trixie** (half the FG). Rejected: the architectural invariant is the thing; half the fleet satisfying it is worse than today's documented-exemption state.
- **Extract a separate "FG-065a Node" + "FG-065b Go" pair**. Rejected: both halves share one principle; splitting them obscures the invariant's reach and doubles the ceremony. Reviewing one PR is clearer.

## Edit catalogue

### 1. `images/go-slim-trixie/` (NEW, 11 files — mirrors FG-061's shape)

- `Dockerfile` — `FROM golang:1.27-trixie` + OCI labels + `apt-upgrade` + `ca-certificates` + `dumb-init` install + no shell removal (slim contract).
- `image.yaml` — `tag: "latest"`, `platforms: [linux/amd64]`, no `depends_on`.
- `PROMISES.yaml` — 8 promises mirroring `node-slim-trixie` (`runtime.go-toolchain`, `files.ca-certificates`, `files.dumb-init`, `apt.freshly-upgraded`, `apt.no-cache` (inverse), `presence.shell` → `image.has-shell` CAP, `shape.size-budget`, `scan.nonzero-accepted`). `spec_version: 1`, `version: "0.1"`.
- `scan-baseline.json` — initial empty critical_cves list.
- `sid-pins/.gitkeep`.
- `tests/smoke_go_version.sh` (expects `go1.27.*`), `smoke_ca_bundle.sh`, `smoke_dumb_init.sh`, `smoke_apt_upgraded.sh`, `smoke_no_apt_cache.sh`, `smoke_has_shell.sh`, `smoke_size.sh`.

### 2. `images/forge-builder-go-trixie/Dockerfile` (EDIT)

- `ARG GO_BASE=golang:1.27-trixie` → `ARG GO_SLIM_REF=ghcr.io/bboortz/go-slim-trixie:latest`
- `FROM ${GO_BASE}` → `FROM ${GO_SLIM_REF}`
- Header comment updated — note FG-065 dogfood transition.

### 3. `images/forge-builder-go-trixie/image.yaml` (EDIT)

- Add `depends_on: [go-slim-trixie]`.

### 4. `images/forge-builder-node-trixie/Dockerfile` (EDIT)

- `ARG NODE_BASE=node:24-trixie-slim` → `ARG NODE_SLIM_REF=ghcr.io/bboortz/node-slim-trixie:latest`
- `FROM ${NODE_BASE}` → `FROM ${NODE_SLIM_REF}`

### 5. `images/forge-builder-node-trixie/image.yaml` (EDIT)

- Add `depends_on: [node-slim-trixie]`.

### 6. `scripts/discover-images.sh`

- `_PRE_BUILDERS=(debian-slim-trixie debian-slim-sid go-slim-trixie node-slim-trixie python-slim-trixie ubuntu-slim-noble)` (6 entries).

### 7. `scripts/verify-no-upstream-drift.sh`

- Add `'golang:1.27-trixie'` to `_UPSTREAM_ANCHORS`.
- `_EXPECTED=5` → `_EXPECTED=6`.

### 8. `scripts/verify-dockerfile-conformance.py`

- `_PRE_BUILDERS` set adds `go-slim-trixie`.
- `_KNOWN_REF_ARGS` set adds `GO_SLIM_REF`.
- Remove `GO_BASE` + `NODE_BASE` — these are now legacy names; the grep rule only allows `*_REF`-suffixed ARGs. After FG-065 no Dockerfile uses the `*_BASE` names.
- NEW rule: every `images/forge-builder-<lang>-trixie/` has a sibling `images/<lang>-slim-trixie/`. If not → lint failure naming the missing pre-builder + the `arch.language-family-image-pair` CAP.

### 9. `scripts/image_from_graph.py`

- `_PRE_BUILDERS` list adds `go-slim-trixie`.
- `_UPSTREAM_NODE_IDS` already has `golang:1.27-trixie` (`UP_GOLANG`). No change needed there.

### 10. `scripts/build-image.sh`

- GO_SLIM_REF auto-build dependency block (mirror of NODE_SLIM_REF).
- GO_SLIM_REF ref-resolution block.
- GO_SLIM_REF forge-local PULL_FLAG guard.
- GO_SLIM_REF `_HAS_LOCAL_DEP` check.
- `--build-arg GO_SLIM_REF="${GO_SLIM_REF}"` in the buildx command.

### 11. `.github/workflows/build.yml`

- Update `publish-pre-builders` tier comment to list 6 pre-builders.

### 12. `docs/CAPABILITIES.md`

- NEW `arch.language-family-image-pair` — architectural invariant: every language family ships both `<lang>-slim-trixie` + `forge-builder-<lang>-trixie`; builder dogfoods pre-builder.
- NEW `build.go-slim-base`.
- EXT `build.pre-builder-tier` (6 members).
- EXT `image.forge-rooted-slim-bases` (_EXPECTED=6; exemption callout retired).
- EXT `build.shared-node-builder` (dogfoods node-slim-trixie).
- EXT `build.shared-go-builder` (dogfoods go-slim-trixie).

### 13. `docs/stories/INDEX.md`

- Add FG-065 row above FG-064.

### 14. `memory/design-decisions.md`

- Retire "dedicated-toolchain exemption" callout.
- Add new section "Language family image pairs" (verbatim from the story).

### 15. `memory/docker-standard.md`

- Update chain-depth example — now 6 pre-builders (not 4); Go reaches 5 hops (at the cap).
- Remove dedicated-toolchain exemption mentions.

### 16. `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh` (NEW)

12 sections encoding the Gherkin scenarios.

### 17. Existing test patches

- `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh` — pre-builder count 5 → 6, alphabetical order list.
- `tests/acceptance/test_FG_061_node-slim-trixie-pre-builder.sh` — same.
- `tests/acceptance/test_FG_046a_forge-builder-go-trixie.sh` — update the FROM assertion from `${GO_BASE}`/`golang:1.27-trixie` to `${GO_SLIM_REF}`.
- `tests/acceptance/test_FG_048a_forge-builder-node-trixie.sh` — update the FROM assertion from `${NODE_BASE}`/`node:24-trixie-slim` to `${NODE_SLIM_REF}`.

### 18. Auto-regenerated

- `docs/image-dependency-graph.md` + `.svg` — regenerated via `make dep-graph`. Expected diff: `golang:1.27-trixie → go-slim-trixie → forge-builder-go-trixie` replaces the direct upstream edge; `node-slim-trixie → forge-builder-node-trixie` replaces the direct upstream edge.

## Merge order

1. Branch `feat/FG-065-forge-builder-dogfood-symmetry` from dev.
2. Create `images/go-slim-trixie/` + flip both Dockerfiles + update both image.yaml.
3. Update all 5 scripts.
4. Update CAPABILITIES + INDEX + both memory files.
5. Write red acceptance test + patch 4 existing tests.
6. Local full-build sweep: go-slim-trixie + FBG + FBN + every downstream Go/Node consumer. All smokes green.
7. Regenerate scan-baseline.json for go-slim-trixie.
8. `make dep-graph` → regen committed.
9. `make check-smart-strict` green locally.
10. PR → CI full-check → auto-merge → release → next cron re-publishes.

## Rollout

- Zero consumer impact. Every from-Go / from-Node image still uses `${FORGE_BUILDER_<X>_REF}` — unchanged.
- First publish: `go-slim-trixie` lands as a new GHCR repo. `forge-builder-{go,node}-trixie`'s next publish picks up the new FROM.
- One-time cache-miss on FBG + FBN apt layers (base changed); shared pre-builder layer cached afterward.

## Breaking changes

None for consumers. Internal: the ARG names `GO_BASE` and `NODE_BASE` are retired. If any external build uses `--build-arg GO_BASE=...` to override, that override stops working. Not a documented public contract.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — go-slim-trixie layout | Scenario 1 | ⏳ |
| Gherkin — go-slim-trixie FROMs upstream | Scenario 2 | ⏳ |
| Gherkin — FBG dogfoods | Scenario 3 | ⏳ |
| Gherkin — FBN dogfoods | Scenario 4 | ⏳ |
| Gherkin — depends_on grows | Scenario 5 | ⏳ |
| Gherkin — pre-builder count 5→6 | Scenario 6 | ⏳ |
| Gherkin — verify-no-upstream-drift | Scenario 7 | ⏳ |
| Gherkin — chain depth ≤ 5 | Scenario 8 | ⏳ |
| Gherkin — downstream smokes green | Scenario 9 | ⏳ |
| Gherkin — dep graph new edges | Scenario 10 | ⏳ |
| Gherkin — memory + design-decisions | Scenario 11 | ⏳ |
| Gherkin — language-pair invariant doc | Scenario 12 | ⏳ |
| Gherkin — conformance lint catches unpaired | Scenario 13 | ⏳ |
| Self-consistency | 2 new CAPs + 4 EXT; bidirectional links | ⏳ |
| No consumer-contract break | zero Dockerfile-body edits in consumers | ✅ |
