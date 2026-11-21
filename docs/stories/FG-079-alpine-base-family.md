---
id: FG-079
slug: alpine-base-family
status: draft
owner: bboortz
created: 2026-11-21
---

# FG-079 — Alpine base family: `pre-builder/alpine-3` + `base/alpine-3` (no builder)

Introduce Alpine as Forge's second OS family (after Debian + Ubuntu). Adds **one new L1 pre-builder + one new L3 base, no L2 builder**. The immediate driver is homelab's `docker/ham-remote/rigctld/` — currently FROMs `alpine:latest` directly + apk-installs `hamlib`. FG-079 unlocks moving that image (and future ones) onto a forge-rooted chain: FG-073 (nginx-scratch-alpine, draft) + any future Alpine-musl runtime becomes a 1-line `FROM ${BASE_ALPINE_REF}` swap.

## Naming — no `-slim`, no decimal version

Alpine ships one flavor (there's no `alpine:3.21-slim` vs `alpine:3.21`). The `-slim` suffix forge uses for Debian/Ubuntu (`pre-builder/debian-slim-trixie`) documents "we picked the slim upstream variant" — not meaningful for Alpine. And unlike Debian codenames (`trixie`, `bookworm`), Alpine only has version numbers. Floating the major version:

- `pre-builder/alpine-3` → FROM `alpine:3` (daily cron picks up `3.N.M` point releases)
- `base/alpine-3` → FROM `pre-builder/alpine-3`

Matches Zig's `pre-builder/zig-slim-trixie` precedent of using a major-version pin (`ZIG_VERSION=0.17.1`) but at the simpler major-only level. Future concrete pins (if needed): `pre-builder/alpine-3.21` as a sibling — parallel to `pre-builder/debian-slim-sid` being a sibling of `pre-builder/debian-slim-trixie`.

## Do we need pre-builder AND builder for Alpine?

| Tier | Needed? | Why |
|---|---|---|
| **L1 `pre-builder/alpine-3`** | ✅ Yes | FG-065 single-upstream-consumer invariant. One forge image FROMs `alpine:3`; `_EXPECTED=6 → 7`. Also shares one apk-upgrade pass across downstream consumers. |
| **L2 `builder/alpine-*`** | ❌ No | L2 builders exist for **language families** (python/go/node/zig) to compile from source. Alpine is an OS family, not a language. We don't have `builder/debian-trixie` or `builder/ubuntu-noble` for the same reason. If a future from-musl-source Go binary ever needs Alpine musl, that'd spawn a dedicated `builder/go-alpine-3` as a language-family pairing (FG-065 `arch.language-family-image-pair` invariant), not a generic `builder/alpine-*`. |
| **L3 `base/alpine-3`** | ✅ Yes | Post-FG-077 public-API foundation. FROMs `pre-builder/alpine-3` + `/hc` + `USER 65532` nonroot baseline. Enables `ham-rigctld-alpine-3` (next FG, homelab-driven) + FG-073 `nginx-scratch-alpine` + any future Alpine consumer to FROM a forge-signed public-API path. |

Mirrors Debian + Ubuntu shape exactly (post-FG-077): **pre-builder + base, no builder**.

## 9 canonical answers

1. **Who** — Forge maintainers (new OS family to maintain); homelab operator (unlock migrating `docker/ham-remote/rigctld/` to a forge-signed image via the follow-up FG); FG-073 nginx-scratch-alpine; future Alpine-musl consumers.
2. **When** — Fires every time a consumer needs an Alpine runtime. Today: homelab's rigctld pulls `alpine:latest` unsigned; FG-073 stuck in draft waiting for a forge-rooted Alpine. After FG-079: one follow-up FG per consumer suffices.
3. **What success looks like** —
   - `images/pre-builder/alpine-3/` published at `ghcr.io/bboortz/pre-builder/alpine-3:latest`. Daily-cron re-pulls + apk-upgrades.
   - `images/base/alpine-3/` published at `ghcr.io/bboortz/base/alpine-3:latest`. FROMs the pre-builder + `/hc` + `USER 65532` + no ENTRYPOINT (Alpine busybox shell is the default).
   - `_EXPECTED=6 → 7` in `verify-no-upstream-drift.sh`; `_UPSTREAM_ALLOWLIST` gains `alpine:3`.
   - `_PRE_BUILDERS` + `_BASELINE` sets grow in 3 scripts; `_INTRA_LAYER_EXEMPTIONS` gains `(base/alpine-3, pre-builder/alpine-3)`.
   - `_KNOWN_REF_ARGS` gains `ALPINE_REF` (upstream) + `BASE_ALPINE_REF` (public API).
   - Chain depth: `alpine:3 → pre-builder/alpine-3 → base/alpine-3 → consumer` = 4 hops. Well under FG-042's 5-hop cap; opens headroom for a future `base/scratch-alpine-3` overlay if needed.
   - Follow-up FG (next) unblocks: forge builds `ham-rigctld-alpine-3` (consuming `base/alpine-3` + installing hamlib + netcat-openbsd), replacing homelab's `docker/ham-remote/rigctld/` recipe.
4. **Urgency** — Quality-of-life. Moderate — no CVE pressure, but homelab's rigctld currently has no supply-chain story (unsigned `alpine:latest` + runtime apk-upgrade).
5. **Happy path** —
   1. Create `images/pre-builder/alpine-3/` with Dockerfile FROMing `alpine:3`, running `apk upgrade --no-cache` + installing `ca-certificates dumb-init` + `update-ca-certificates`.
   2. Create `images/base/alpine-3/` with Dockerfile FROMing the pre-builder, `COPY --from=hc /hc /hc`, `USER 65532`.
   3. PROMISES + EXPECTATIONS + scan-baseline + smoke tests per image.
   4. Tooling updates (see §tooling below).
   5. CAPs + dep graph regen + `make test-fast`.
   6. PR + CI + merge + release + publish.
6. **Edge cases / failure modes** —
   - **apk vs apt**: Pre-builder shape differs from Debian/Ubuntu siblings. PROMISES rename `apt.freshly-upgraded` → `apk.freshly-upgraded`; `apt.no-cache` → `apk.no-cache`.
   - **CA bundle path**: Alpine ships `/etc/ssl/certs/ca-certificates.crt` via `ca-certificates` + `update-ca-certificates`. Same path as Debian post-install → base/alpine-3's `files.ca-certificates` PROMISE wording matches debian/ubuntu's.
   - **dumb-init availability**: in Alpine's `community` repository (enabled by default on `alpine:3` Docker image).
   - **USER 65532 lookup**: Alpine's `/etc/passwd` doesn't have a user at uid 65532. Numeric USER works for Docker; consumers that do `id -un` or `getpwuid()` will see uid-only resolution. Document in PROMISES: "numeric uid only; no `/etc/passwd` entry — consumers needing `getpwuid` must add a user line or run as a known Alpine uid like `nobody` (65534)."
   - **musl vs glibc**: `base/scratch-trixie` overlay-COPY can't be consumed by Alpine runtimes (libc ABI mismatch). Any future `base/scratch-alpine-3` would need a separate glibc-free overlay. Not in scope.
7. **Out of scope** —
   - No `builder/alpine-*`.
   - No `base/scratch-alpine-3` or `base/<lang>-scratch-alpine-3` (musl scratch overlays).
   - No ham-rigctld-alpine-3 runtime image — separate follow-up FG consumes `base/alpine-3` to replace homelab's `docker/ham-remote/rigctld/`.
   - No nginx-scratch-alpine implementation (FG-073 stays as a separate draft, unblocked by FG-079).
   - L0.1 inventory does NOT grow — Alpine is an L0 Docker Hub image, not an L0.1 source.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_079_alpine-base-family.sh`. Pre-builder + base both build locally; both tags live on GHCR; `_EXPECTED=7`; dep graph shows both in L1 + L3 subgraphs.
9. **Capabilities delivered or extended** —
   - NEW `arch.alpine-pre-builder` — `pre-builder/alpine-3` published; `_EXPECTED=7` tracks the new upstream anchor.
   - NEW `image.alpine-foundation` — `base/alpine-3` public-API Alpine foundation; parallel to `image.debian-slim-foundation` + `image.ubuntu-slim-foundation`.
   - EXT `arch.base-tier-public-api` — Alpine joins the base/* tier.

## Follow-up FG (separate story)

After FG-079 ships, next FG replaces homelab's `docker/ham-remote/rigctld/`:

```
images/ham-rigctld-alpine-3/
  Dockerfile:
    FROM ${BASE_ALPINE_REF}
    USER 0
    RUN apk add --no-cache hamlib netcat-openbsd
    COPY start.sh /start.sh
    ENV RIG_MODEL=1049 CAT_DEVICE=/dev/ttyUSB0 RIG_BAUD=38400 RIGCTLD_PORT=4532
    USER 65532  # or dedicated user — see §USER 65532 lookup edge case
    CMD ["/start.sh"]
```

Homelab's `docker/ham-remote/rigctld/` deletes; its compose stack reads `image: ghcr.io/bboortz/ham-rigctld-alpine-3:latest`.

## Tooling updates (for FG-079 implementation)

| File | Change |
|---|---|
| `scripts/verify-no-upstream-drift.sh` | `_EXPECTED=6 → 7`; add `alpine:3` to upstream anchors |
| `scripts/verify-dockerfile-conformance.py` | `_PRE_BUILDERS` += `pre-builder/alpine-3`; `_BASELINE` += `base/alpine-3`; `_KNOWN_REF_ARGS` += `ALPINE_REF, BASE_ALPINE_REF`; `_INTRA_LAYER_EXEMPTIONS` += `(base/alpine-3, pre-builder/alpine-3)`; `_UPSTREAM_ALLOWLIST` += `alpine:3` |
| `scripts/image_from_graph.py` | `_PRE_BUILDERS` + `_BASELINE` lists grow; `_UPSTREAM_ANCHORS` += `alpine:3` |
| `scripts/discover-images.sh` | `_PRE_BUILDERS` += `pre-builder/alpine-3` |
| `scripts/build-image.sh` | Add `ALPINE_REF` + `BASE_ALPINE_REF` resolver blocks + on-demand builder + build-arg passes + PULL_FLAG guards + `_HAS_LOCAL_DEP` checks |
| `docs/LAYERING.md` | §3 L0 add `alpine:3`; §3 L1 count 7→8; §3 L3 add `base/alpine-3`; §7 chain-depth add Alpine row |
| `memory/docker-standard.md` | §7-tier add alpine mention; chain-depth paragraph add Alpine row |

## Gherkin acceptance

```
Scenario: pre-builder + base both exist
  Given FG-079 has shipped
  When I ls images/pre-builder/ and images/base/
  Then pre-builder/alpine-3 + base/alpine-3 are present

Scenario: _EXPECTED drift guard moved from 6 to 7
  Given FG-079 has shipped
  Then scripts/verify-no-upstream-drift.sh has _EXPECTED=7
   And verify-no-upstream-drift.sh exits 0

Scenario: both images build + smokes pass
  Given FG-079 has shipped
  When I run bash scripts/build-image.sh pre-builder/alpine-3
   And bash scripts/build-image.sh base/alpine-3
  Then both succeed
   And every smoke script under their tests/ exits 0

Scenario: no builder/alpine-*
  Given FG-079 has shipped
  Then images/builder/ contains no alpine-* entry

Scenario: ham-rigctld-alpine-3 (next FG) can consume base/alpine-3
  Given FG-079 has shipped
  When the follow-up FG lands a from-base/alpine-3 image
  Then its Dockerfile FROMs ${BASE_ALPINE_REF} not alpine:* literally
   And homelab's docker/ham-remote/rigctld/ can be deleted in a paired PR
```

## References

- Driver: homelab's `docker/ham-remote/rigctld/Dockerfile` (`FROM alpine:latest` + apk hamlib)
- Downstream future: FG-073 nginx-scratch-alpine (draft); any future Alpine runtime
- Parent: `docs/plan/tier-layering-model.md` §3 L1 + §3 L3 (shape rules for OS families)
- Pattern precedent: `pre-builder/debian-slim-trixie` + `base/debian-slim-trixie` (post-FG-077)
- Design decisions: `memory/design-decisions.md` § Debian trixie (not Wolfi, not Alpine) — Alpine remains a case-by-case OS family addition like Ubuntu. FG-079 is Alpine's first-precedent story.
- Plan: `docs/plan/FG-079-alpine-base-family-plan.md` (to be created when FG-079 enters ready state)
- Red test: `tests/acceptance/test_FG_079_alpine-base-family.sh`
