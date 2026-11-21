---
id: FG-081
slug: archlinux-base-family
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-081 — Arch Linux base family: `pre-builder/archlinux` + `base/archlinux` (no builder)

Introduce Arch Linux as Forge's third OS family (after Debian + Ubuntu + Alpine). **Immediate driver**: homelab's `docker/gamepad/Dockerfile` currently FROMs `archlinux:latest` unsigned + runs `pacman -Syu` + installs `python python-pip python-evdev`. FG-081 unlocks moving that image onto a forge-rooted chain: homelab deletes its local Dockerfile; compose reads `image: ghcr.io/bboortz/gamepad-archlinux:latest` (next FG).

Shape mirrors FG-079 (Alpine): pre-builder + base, no builder. Arch is an OS family, not a language family — no L2 builder.

## Why Arch (not Debian/Alpine) for gamepad

Homelab's gamepad needs `python-evdev` to access `/dev/input/*` for joystick/gamepad event parsing. The Arch package tree ships recent `python-evdev` (currently 1.9+) with kernel-ABI-matched build. Debian trixie and Alpine 3.x both ship older versions tied to their own release cadence. The gamepad container is already on Arch; FG-081 just moves the supply chain under Forge's signature + daily-cron patch coverage.

## 9 canonical answers

1. **Who** — Forge maintainers (new OS family to maintain); homelab operator (unlock migrating `docker/gamepad/` to a forge-signed image via the follow-up FG).
2. **When** — Fires every time a homelab or external consumer needs an Arch Linux runtime. Today: gamepad pulls `archlinux:latest` unsigned. After FG-081: one follow-up FG per consumer suffices.
3. **What success looks like** —
   - `images/pre-builder/archlinux/` published at `ghcr.io/bboortz/pre-builder/archlinux:latest`. Daily-cron re-pulls + `pacman -Syu` + installs `ca-certificates dumb-init`.
   - `images/base/archlinux/` published at `ghcr.io/bboortz/base/archlinux:latest`. FROMs the pre-builder + `/hc` + `USER 65532` + no ENTRYPOINT (Arch's `/bin/bash` is the default).
   - `_EXPECTED=7 → 8` in `verify-no-upstream-drift.sh`; `_UPSTREAM_ALLOWLIST` gains `archlinux:latest`.
   - `_PRE_BUILDERS` + `_BASELINE` sets grow in 3 scripts; `_INTRA_LAYER_EXEMPTIONS` gains `(base/archlinux, pre-builder/archlinux)`.
   - `_KNOWN_REF_ARGS` gains `ARCHLINUX_REF` (internal) + `BASE_ARCHLINUX_REF` (public API).
   - Chain depth: `archlinux:latest → pre-builder/archlinux → base/archlinux → consumer` = 3 hops. Well under FG-042's 5-hop cap.
   - Follow-up FG unblocks: forge builds `gamepad-archlinux` (consuming `base/archlinux` + pacman-installing python + python-evdev), replacing homelab's `docker/gamepad/` recipe.
4. **Urgency** — Quality-of-life. Moderate — homelab's gamepad currently has no CVE-scan or cosign-verify story.
5. **Happy path** —
   1. Create `images/pre-builder/archlinux/` with Dockerfile FROMing `archlinux:latest`, running `pacman -Syu --noconfirm` + installing `ca-certificates dumb-init` + `pacman -Scc --noconfirm` to clear cache.
   2. Create `images/base/archlinux/` with Dockerfile FROMing the pre-builder, `COPY --from=hc /hc /hc`, `USER 65532`.
   3. PROMISES + EXPECTATIONS + scan-baseline + smoke tests per image.
   4. Tooling updates (see §tooling).
   5. CAPs + dep graph regen + `make test-fast`.
6. **Edge cases / failure modes** —
   - **Rolling-release drift**: Unlike Debian trixie (stable) or Alpine 3 (minor-stable), Arch rolls forward daily. `pacman -Syu` can pull in kernel-ABI-breaking updates, GCC bumps, etc. Daily-cron rebuilds absorb this; scan-baseline.json will drift more than any other pre-builder. Accept nonzero CRITICAL scans via `absence.os-cves.waivers` pattern or rely on `scan.nonzero-accepted` category (parallel to `debian-slim-sid`'s rolling status).
   - **archlinux:latest hadolint DL3007**: warn against `:latest`. Add `# hadolint ignore=DL3007` in the pre-builder Dockerfile; Arch has no versioned tag that makes sense (date-stamped tags like `archlinux:base-20251101.0.123456` require manual pinning per rebuild and defeat the cron-rolling model). Documented exemption.
   - **USER 65532 lookup**: Arch's `/etc/passwd` has no entry at uid 65532. Numeric uid works; consumers using `getpwuid()` must add a passwd line. Same caveat as Alpine (FG-079).
   - **Image size**: Arch's `archlinux:latest` is ~400 MB (vs Debian trixie-slim ~75 MB, Alpine 3 ~8 MB). Pre-builder budget should be 1.5× to cover `pacman -Syu` delta + CA + dumb-init. No apology — Arch's larger size is the trade-off for rolling-current packages.
   - **pacman cleanup**: `pacman -Scc --noconfirm` is required; otherwise the apk-equivalent of `/var/cache/pacman/pkg/*` persists and bloats the image.
   - **No "minimal" variant**: unlike Debian's `-slim` / Alpine's base, Arch's `archlinux:latest` IS the minimal variant. The pre-builder is what forge adds (apt-equivalent upgrade + CA).
   - **No dumb-init shipped**: neither `dumb-init` nor `tini` live in Arch's core/extra repos (only AUR, which forge doesn't trust without makepkg from base-devel). Delta vs other forge pre-builders (Debian/Ubuntu/Alpine all ship dumb-init). Consumers that need PID-1 signal handling install their own or COPY-from a dumb-init builder stage. Documented in the pre-builder's PROMISES.yaml as an absence.
7. **Out of scope** —
   - No `builder/archlinux-*` (Arch is an OS family, not a language family).
   - No `base/scratch-archlinux` (glibc-scratch overlay already exists as `base/scratch-trixie`; if a consumer needs Arch-glibc specifically, revisit — unlikely).
   - No `gamepad-archlinux` runtime image — separate follow-up FG.
   - L0.1 inventory stays unchanged (Arch is an L0 Docker Hub image, not an L0.1 source).
   - No specific Arch minor version pinning. Rolling is the model.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_081_archlinux-base-family.sh`. Pre-builder + base both build locally; both tags live on GHCR; `_EXPECTED=8`; dep graph shows both in L1 + L3 subgraphs.
9. **Capabilities delivered or extended** —
   - NEW `arch.archlinux-pre-builder` — `pre-builder/archlinux` published; `_EXPECTED=8` tracks the new upstream anchor.
   - NEW `image.archlinux-foundation` — `base/archlinux` public-API Arch foundation; parallel to `image.{debian,ubuntu,alpine}-foundation`.
   - EXT `arch.base-tier-public-api` — Arch joins the base/* tier.

## Tooling updates

| File | Change |
|---|---|
| `scripts/verify-no-upstream-drift.sh` | `_EXPECTED=7 → 8`; `_UPSTREAM_ANCHORS += archlinux:latest` |
| `scripts/verify-dockerfile-conformance.py` | `_PRE_BUILDERS += pre-builder/archlinux`; `_BASELINE += base/archlinux`; `_UPSTREAM_ALLOWLIST += archlinux:latest`; `_KNOWN_REF_ARGS += ARCHLINUX_REF, BASE_ARCHLINUX_REF`; `_INTRA_LAYER_EXEMPTIONS += (base/archlinux, pre-builder/archlinux)` |
| `scripts/image_from_graph.py` | `_PRE_BUILDERS` + `_BASELINE` lists grow; `_UPSTREAM_NODE_IDS` gains `archlinux:latest → UP_ARCHLINUX`; `_UPSTREAM_ANCHORS` += |
| `scripts/discover-images.sh` | `_PRE_BUILDERS += pre-builder/archlinux` |
| `scripts/build-image.sh` | Add `ARCHLINUX_REF` + `BASE_ARCHLINUX_REF` resolver blocks + on-demand builder + build-arg passes + PULL_FLAG guards + `_HAS_LOCAL_DEP` checks |

## Gherkin acceptance

```
Scenario: pre-builder + base both exist
  Given FG-081 has shipped
  When I ls images/pre-builder/ and images/base/
  Then pre-builder/archlinux + base/archlinux are present

Scenario: _EXPECTED drift guard 7 → 8
  Given FG-081 has shipped
  Then scripts/verify-no-upstream-drift.sh has _EXPECTED=8
   And verify-no-upstream-drift.sh exits 0

Scenario: both images build + smokes pass
  Given FG-081 has shipped
  When I run bash scripts/build-image.sh pre-builder/archlinux
   And bash scripts/build-image.sh base/archlinux
  Then both succeed
   And every smoke script under their tests/ exits 0

Scenario: no builder/archlinux-*
  Given FG-081 has shipped
  Then images/builder/ contains no archlinux-* entry

Scenario: gamepad-archlinux (next FG) can consume base/archlinux
  Given FG-081 has shipped
  When the follow-up FG lands a from-base/archlinux image
  Then its Dockerfile FROMs ${BASE_ARCHLINUX_REF} not archlinux:* literally
   And homelab's docker/gamepad/ can be deleted in a paired PR
```

## References

- Driver: homelab's `docker/gamepad/Dockerfile` (`FROM archlinux:latest` + pacman python-evdev)
- Pattern precedent: `pre-builder/alpine-3` + `base/alpine-3` (FG-079 — parallel OS-family addition)
- Design decisions: `memory/design-decisions.md` § Debian trixie (not Wolfi, not Alpine) — Arch is a case-by-case OS family addition. FG-081 adds the third precedent after Ubuntu (FG-051) and Alpine (FG-079).
- Plan: `docs/plan/FG-081-archlinux-base-family-plan.md` (to be created when FG-081 enters ready state)
- Red test: `tests/acceptance/test_FG_081_archlinux-base-family.sh`
