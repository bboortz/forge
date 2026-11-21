# FG-081 — Plan: Arch Linux base family (pre-builder + base, no builder)

**Story**: [`docs/stories/FG-081-archlinux-base-family.md`](../stories/FG-081-archlinux-base-family.md)
**Status**: ready → shipped
**Branch**: `feat/FG-081-archlinux-base-family`

## Design delta

2 new images, third OS family (parallel to Debian + Ubuntu + Alpine).

**L1** `pre-builder/archlinux` — Dockerfile FROMs `archlinux:latest`, runs `pacman -Syu --noconfirm ca-certificates` + `pacman -Scc --noconfirm` (clear cache). Single-stage. Same shape as `pre-builder/alpine-3` but with pacman instead of apk. **Delta vs other forge pre-builders**: dumb-init is NOT shipped (neither dumb-init nor tini in Arch's core/extra; AUR-only, forge doesn't trust it without base-devel+makepkg). Consumers install their own.

**L3** `base/archlinux` — Dockerfile FROMs `${ARCHLINUX_REF}` (pre-builder) + `COPY --from=hc /hc /hc` + `USER 65532`. No ENTRYPOINT (Arch's `/bin/bash` is the default). Same shape as `base/alpine-3`.

L2 `builder/archlinux-*` **explicitly not included** — L2 builders are for language families (python/go/node/zig), not OS families. Documented in story + CAP descriptions.

## Alternatives rejected

- **`FROM archlinux:base-YYYYMMDD.X.NNNNNN` (date-stamped pin)** — defeats cron-rolling; requires manual bump per rebuild. Rejected. `archlinux:latest` + daily cron re-resolves is the model (parallel to `debian-slim-sid`'s rolling status).
- **Combine pre-builder + base into one image** — breaks the FG-077 public/internal boundary. Reject.
- **Skip `base/archlinux` + have consumers FROM `pre-builder/archlinux` directly** — violates FG-075 public-API rule (consumers must not FROM pre-builder/*).
- **Use `archlinux/archlinux:base-devel`** — ships gcc + binutils + make unnecessarily for a pre-builder; adds ~400 MB. `archlinux:latest` (= `base`) is the correct minimal upstream.

## Breaking changes

None. New OS family; no existing image changes.

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI acceptance suite. Build + smoke locally.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` → publishes `ghcr.io/bboortz/pre-builder/archlinux:latest` + `ghcr.io/bboortz/base/archlinux:latest` (publish-pre-builders → publish-base ordering, fixed by FG-077)
4. Verify tags via `docker manifest inspect`
5. Follow-up FG (separate story): forge builds `gamepad-archlinux` consuming `base/archlinux` + pacman-installing python + python-evdev; paired homelab PR deletes `docker/gamepad/`

## Tooling updates (concrete list)

| File | Change |
|---|---|
| `scripts/verify-no-upstream-drift.sh` | `_EXPECTED=7 → 8`; `_UPSTREAM_ANCHORS += archlinux:latest` |
| `scripts/verify-dockerfile-conformance.py` | `_PRE_BUILDERS += pre-builder/archlinux`; `_BASELINE += base/archlinux`; `_UPSTREAM_ALLOWLIST += archlinux:latest`; `_KNOWN_REF_ARGS += ARCHLINUX_REF, BASE_ARCHLINUX_REF`; `_INTRA_LAYER_EXEMPTIONS += (base/archlinux, pre-builder/archlinux)` |
| `scripts/image_from_graph.py` | `_PRE_BUILDERS` + `_BASELINE` lists grow; `_UPSTREAM_NODE_IDS` gains `archlinux:latest` → `UP_ARCHLINUX` |
| `scripts/discover-images.sh` | `_PRE_BUILDERS += pre-builder/archlinux` |
| `scripts/build-image.sh` | Add `ARCHLINUX_REF` + `BASE_ARCHLINUX_REF` resolver blocks + build-arg passes + PULL_FLAG guards + `_HAS_LOCAL_DEP` checks + on-demand builder cases |

## Shipping evidence

Filled at pre-ship audit.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: pre-builder + base both exist | `tests/acceptance/test_FG_081_archlinux-base-family.sh:§1` | ✅ |
| Scenario: _EXPECTED drift guard 7→8 | test §2 | ✅ |
| Scenario: both images build + smokes pass | test §3 | ✅ |
| Scenario: no builder/archlinux-* | test §4 | ✅ |
| CAP `arch.archlinux-pre-builder` | test + CAPABILITIES | ✅ |
| CAP `image.archlinux-foundation` | test + CAPABILITIES | ✅ |
