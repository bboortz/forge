# FG-079 — Plan: Alpine base family (pre-builder + base, no builder)

**Story**: [`docs/stories/FG-079-alpine-base-family.md`](../stories/FG-079-alpine-base-family.md)
**Status**: ready → shipped
**Branch**: `feat/FG-079-alpine-base-family`

## Design delta

2 new images, 1 new OS family (parallel to Debian + Ubuntu).

**L1** `pre-builder/alpine-3` — Dockerfile FROMs `alpine:3`, runs `apk upgrade --no-cache` + installs `ca-certificates dumb-init` + `update-ca-certificates`. Single-stage. Same shape as `pre-builder/debian-slim-trixie` but with apk instead of apt.

**L3** `base/alpine-3` — Dockerfile FROMs `${ALPINE_REF}` (pre-builder) + `COPY --from=hc /hc /hc` + `USER 65532`. No ENTRYPOINT (Alpine busybox shell is the default). Same shape as `base/debian-slim-trixie`.

L2 `builder/alpine-*` **explicitly not included** — L2 builders are for language families (python/go/node/zig), not OS families. Documented in story + CAP descriptions.

## Alternatives rejected

- **`FROM alpine:latest`** — hadolint DL3007 warn; silent major-version rolls. Rejected per story's tag-pin discussion.
- **`FROM alpine:3.21` (explicit minor)** — valid future precedent but less flexible for daily cron. `alpine:3` + a separate `pre-builder/alpine-3.21` sibling (parallel to `debian-slim-sid` sibling of `debian-slim-trixie`) is the cleaner escape hatch.
- **Combine pre-builder + base into one image** — breaks the FG-077 public/internal boundary. Reject.
- **Skip `base/alpine-3` + have consumers FROM `pre-builder/alpine-3` directly** — violates FG-075 public-API rule (consumers must not FROM pre-builder/*).

## Breaking changes

None. New family; no existing image changes.

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI acceptance suite. Build + smoke locally.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` → publishes `ghcr.io/bboortz/pre-builder/alpine-3:latest` + `ghcr.io/bboortz/base/alpine-3:latest` (publish-pre-builders → publish-base ordering fixed by FG-077)
4. Verify tags via `docker manifest inspect`
5. Follow-up FG (separate story): forge builds `ham-rigctld-alpine-3` consuming `base/alpine-3`; paired homelab PR deletes `docker/ham-remote/rigctld/`

## Tooling updates (concrete list)

| File | Change |
|---|---|
| `scripts/verify-no-upstream-drift.sh` | `_EXPECTED=6 → 7`; `_UPSTREAM_ANCHORS += alpine:3` |
| `scripts/verify-dockerfile-conformance.py` | `_PRE_BUILDERS += pre-builder/alpine-3`; `_BASELINE += base/alpine-3`; `_UPSTREAM_ALLOWLIST += alpine:3`; `_KNOWN_REF_ARGS += ALPINE_REF, BASE_ALPINE_REF`; `_INTRA_LAYER_EXEMPTIONS += (base/alpine-3, pre-builder/alpine-3)` |
| `scripts/image_from_graph.py` | `_PRE_BUILDERS` + `_BASELINE` lists grow; `_UPSTREAM_NODE_IDS` gains `alpine:3` → `UP_ALPINE` |
| `scripts/discover-images.sh` | `_PRE_BUILDERS += pre-builder/alpine-3` |
| `scripts/build-image.sh` | Add `ALPINE_REF` + `BASE_ALPINE_REF` resolver blocks + build-arg passes + PULL_FLAG guards + `_HAS_LOCAL_DEP` checks + on-demand builder cases |

## Shipping evidence

Filled at pre-ship audit.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: pre-builder + base both exist | `tests/acceptance/test_FG_079_alpine-base-family.sh:§1` | ✅ |
| Scenario: _EXPECTED drift guard 6→7 | test §2 | ✅ |
| Scenario: both images build + smokes pass | test §3 | ✅ |
| Scenario: no builder/alpine-* | test §4 | ✅ |
| CAP `arch.alpine-pre-builder` | test + CAPABILITIES | ✅ |
| CAP `image.alpine-foundation` | test + CAPABILITIES | ✅ |
