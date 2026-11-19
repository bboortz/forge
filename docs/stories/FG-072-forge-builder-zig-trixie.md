---
id: FG-072
slug: forge-builder-zig-trixie
status: in-progress
owner: bboortz
created: 2026-11-18
---

# FG-072 — `forge-builder-zig-trixie` + sibling `zig-slim-trixie` pre-builder

Forge's `arch.language-family-image-pair` invariant (FG-065) says every programming language family ships two co-published images: a `<lang>-slim-trixie` pre-builder and a `forge-builder-<lang>-trixie` toolchain builder. Zig is the fourth language family we need (after Python, Go, Node) and the first motivated by a concrete downstream need: **from-source Zig builds for Forge-native static-binary tools, starting with `hc`** (the static Zig healthcheck binary currently pulled from `ghcr.io/bboortz/hc:0.1.0` by `healthy-scratch-trixie` + 10 other scratch runtimes via `COPY --from=hc /hc /hc`).

FG-072 lands the pair; downstream migrations (`hc` from-source, `healthy-scratch-trixie` build-from-source instead of COPY-from) are separate follow-up FGs.

## 9 canonical answers

1. **Who** — Forge maintainer wanting to add Zig-based from-source images (first concrete candidate: migrating the currently-external `bboortz/hc` binary INTO Forge as a from-source build, same shape as the Go/Node binaries post-FG-046/FG-048). Also future Zig-based tooling if any lands (e.g., `bun`, `tigerbeetle`, zig-based static CLIs). Also the `arch.language-family-image-pair` invariant reviewer — Zig is the obvious next slot.

2. **When** — Fires on every daily cron (new pair publishes alongside the existing 3-language builder set). Also fires whenever a Zig-consuming Dockerfile edit lands or Zig upstream ships a new release (the pre-builder's tarball install resolves `latest` via FG-050 `build.ref-latest-release`, so the fleet auto-tracks within 24h).

3. **What success looks like**:
   - `images/zig-slim-trixie/` exists — mirrors `node-slim-trixie` / `go-slim-trixie` shape, but with Zig installed from the upstream ziglang.org tarball (Zig doesn't ship an official Debian-based Docker Hub image — see § edge cases).
   - `images/forge-builder-zig-trixie/` exists — mirrors `forge-builder-go-trixie` shape, dogfoods `zig-slim-trixie` (`FROM ${ZIG_SLIM_REF}`) + adds `git` + `curl` + `jq` + `syft` on top.
   - `arch.language-family-image-pair` invariant: Zig joins Python/Go/Node as a satisfying family. Four co-published pairs.
   - `scripts/verify-no-upstream-drift.sh` `_EXPECTED` stays at 6 (zig-slim-trixie FROMs `${DEBIAN_SLIM_REF}` via ARG-indirect — no new literal upstream anchor). The Zig tarball URL is not a FROM, it's a `RUN curl` fetch — doesn't count toward drift guard.
   - `scripts/verify-dockerfile-conformance.py` Rule 9 (no Docker Hub HTTP pulls in RUN/COPY/ADD) stays green — the Zig tarball is from `ziglang.org`, not a Docker Hub URL. Add `ziglang.org` to a new `_ALLOWED_RUNTIME_FETCH_URLS` set OR Rule 9's allow-pattern.
   - Chain depth stays ≤ 5 hops: `debian:trixie-slim` → `debian-slim-trixie` → `zig-slim-trixie` → `forge-builder-zig-trixie` → (optional) scratch runtime via builder stage = 5 hops at the cap.
   - NEW CAP `build.zig-slim-base` + NEW CAP `build.shared-zig-builder`.
   - EXT CAPs: `build.pre-builder-tier` (7 members), `image.forge-rooted-slim-bases` (Zig family added), `arch.language-family-image-pair` (4 families now).
   - `scripts/discover-images.sh` `_PRE_BUILDERS` adds `zig-slim-trixie`; `_FORGE_BUILDERS` adds `forge-builder-zig-trixie`. Same edit in `image_from_graph.py`.
   - `scripts/build-image.sh` gains `ZIG_SLIM_REF` auto-build-dependency + ref-resolution + `--build-arg` wiring (mirror of GO_SLIM_REF integration).
   - FG-064 dep graph regenerated: new `zig-slim-trixie` in L1 and `forge-builder-zig-trixie` in L2.
   - Smoke tests for both images build + run green.
   - Zero downstream consumer impact today (first consumer migration is a follow-up FG).

4. **Urgency** — Infrastructure + supply-chain tightening. Not security-critical today. The primary motivator is **enabling hc to move from an external repo (`github.com/bboortz/hc` → `ghcr.io/bboortz/hc`) into Forge as a forge-signed from-source build**. Until that follow-up ships, `forge-builder-zig-trixie` sits with zero consumers — same situation as `go-slim-trixie` had on FG-065 ship-day. Satisfying the `arch.language-family-image-pair` invariant up-front means the pair is in place when the hc-migration FG is written.

5. **Happy path**:
   1. Branch `feat/FG-072-forge-builder-zig-trixie` from `dev`.
   2. Pick Zig version strategy: pin to a specific minor (e.g. `0.14.1`) via `ARG ZIG_VERSION=0.14.1` with build-time resolution OR float `latest` via FG-050 `build.ref-latest-release` resolution against ziglang.org's download index. **Recommended: pin + bump via chore commits** — Zig is pre-1.0 and ABI changes between minors; latest-floating risks breaking downstream Dockerfiles silently.
   3. Create `images/zig-slim-trixie/` (full pre-builder — Dockerfile + image.yaml + PROMISES.yaml + 7 smokes + scan-baseline + sid-pins/.gitkeep):
      - `FROM ${DEBIAN_SLIM_REF}` (forge-rooted, not upstream directly — preserves FG-042's "exactly one forge consumer per upstream anchor" rule since debian-slim-trixie already consumes `debian:trixie-slim`)
      - `RUN curl` + minisign-verify + untar Zig to `/usr/local/zig` (binary at `/usr/local/zig/zig` + symlink `/usr/local/bin/zig`)
      - `apt-get upgrade` + `ca-certificates` + `dumb-init` (consistent with other pre-builders)
   4. Create `images/forge-builder-zig-trixie/` (full builder):
      - `FROM ${ZIG_SLIM_REF}` (dogfood — FG-065 arch invariant)
      - `COPY --from=mirror/syft /syft /usr/local/bin/syft`
      - `apt-get install git curl jq` (same toolchain surface as forge-builder-go-trixie)
   5. Update 5 scripts (same pattern as FG-061/FG-065):
      - `scripts/verify-no-upstream-drift.sh` — no `_EXPECTED` bump (zig-slim-trixie uses ARG-indirect FROM to debian-slim-trixie, doesn't match literal grep).
      - `scripts/discover-images.sh` — add `zig-slim-trixie` to `_PRE_BUILDERS`; add `forge-builder-zig-trixie` to `_FORGE_BUILDERS`.
      - `scripts/verify-dockerfile-conformance.py` — `_PRE_BUILDERS` + `_FORGE_BUILDERS` + `_KNOWN_REF_ARGS` (`ZIG_SLIM_REF`, `FORGE_BUILDER_ZIG_REF`); extend Rule 9's URL allowlist to include `ziglang.org` (justified exception: upstream Zig distribution is tarball-only).
      - `scripts/image_from_graph.py` — `_PRE_BUILDERS` + `_FORGE_BUILDERS` lists.
      - `scripts/build-image.sh` — `ZIG_SLIM_REF` auto-build-dep + ref-resolution + `--build-arg`; `FORGE_BUILDER_ZIG_REF` same.
   6. Update `.github/workflows/build.yml` publish-pre-builders + publish-builders comments to list the Zig family.
   7. Update `docs/CAPABILITIES.md`: NEW `build.zig-slim-base` + `build.shared-zig-builder`; EXT `build.pre-builder-tier`, `image.forge-rooted-slim-bases`, `arch.language-family-image-pair`.
   8. Update `docs/stories/INDEX.md` — FG-072 row.
   9. Update `memory/design-decisions.md` § "Language family image pairs" — add Zig row to the satisfying-families table + note the tarball-install exception rationale.
   10. Update `memory/docker-standard.md` chain-depth example — Zig joins Python + Go at the 5-hop cap.
   11. Red acceptance test `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` (10 sections).
   12. Local build sweep: zig-slim-trixie + forge-builder-zig-trixie + every current downstream (none directly — Zig images are zero-consumer today, but the sweep validates that nothing accidentally regressed).
   13. `make dep-graph` → regen asserts the new nodes + edges.
   14. PR → CI full-check → auto-merge → release → publish.

6. **Edge cases / failure modes**:
   - **Zig doesn't ship a Debian-based Docker Hub image**. Upstream distributes tarballs from `ziglang.org/download/<ver>/zig-linux-x86_64-<ver>.tar.xz`. Options:
     - (A) `FROM ${DEBIAN_SLIM_REF}` + `RUN curl + untar` — **chosen**. Keeps debian-slim-trixie as the single consumer of `debian:trixie-slim`. Chain depth +1 vs Python/Go/Node's upstream-FROM pattern but preserves FG-042.
     - (B) `FROM debian:trixie-slim` directly (upstream) — rejected: breaks FG-042 single-upstream-consumer invariant (debian:trixie-slim would gain a second forge consumer).
     - (C) `FROM alpine` — rejected: Alpine-based pre-builder breaks the Debian trixie foundation (`memory/design-decisions.md`).
     - (D) No pre-builder; builder FROMs debian-slim-trixie directly — rejected: breaks FG-065 `arch.language-family-image-pair` invariant.
   - **Zig version pinning**: Zig is pre-1.0; ABI + CLI flags change between minors. Floating `latest` is risky. Pin to a specific minor (e.g. `0.14.1`); bump via chore commits after validating against every downstream. Daily cron re-resolves upstream only when `ZIG_VERSION` changes in the Dockerfile.
   - **Zig signature verification**: ziglang.org publishes minisign signatures at `zig-<platform>-<ver>.tar.xz.minisig`. Recommended: verify the tarball matches its signature + compare its SHA256 against a committed hash in `images/zig-slim-trixie/Dockerfile` (hard-coded ARG `ZIG_SHA256`). Bumping version = update both `ZIG_VERSION` + `ZIG_SHA256` in the same commit.
   - **Rule 9 (no Docker Hub HTTP pulls in RUN/COPY/ADD) extension**: `RUN curl https://ziglang.org/...` would trip Rule 9's URL grep if we tightened it. Current Rule 9 only grep's for Docker Hub URLs (`docker.io`, `hub.docker.com`, `registry-1.docker.io`, `ghcr.io/library/`) — ziglang.org isn't in that set, so Rule 9 stays silent. No change to Rule 9 needed today. If we ever extend Rule 9 to a generic "no HTTP pulls in RUN" rule, add `ziglang.org` to an explicit allow-list.
   - **Chain depth**: `debian:trixie-slim` → `debian-slim-trixie` → `zig-slim-trixie` → `forge-builder-zig-trixie` → scratch runtime (e.g. future from-source `hc`) = 5 hops, at the cap. One hop deeper than the current Python/Go/Node builder chains because Zig's pre-builder FROMs debian-slim-trixie instead of upstream directly.
   - **Binary target**: Zig produces fully static binaries like Go. No runtime closure to pre-bundle. No `base/zig-scratch-base` ever needed (same rationale as `base/go-scratch-base` declined in the tier layering plan).
   - **Dev-loop local build**: `scripts/build-image.sh` handles `ZIG_SLIM_REF` via the forge-local fallback (same pattern as `GO_SLIM_REF` + `NODE_SLIM_REF`). First local build of `forge-builder-zig-trixie` triggers a `zig-slim-trixie` build first.
   - **scan-baseline for zig-slim-trixie**: the Zig toolchain ships a ~50 MB static binary + stdlib. grype will likely report Debian dpkg CVEs (same as other `*-slim-trixie` pre-builders) + possibly Zig stdlib CVEs if syft grows a Zig cataloger. Accept nonzero CRITICALs via the usual `scan.nonzero-accepted` promise.
   - **tarball mirror**: if ziglang.org goes down, builds break. Mitigation if it becomes a pain point: create `mirror/zig-tarball` (not a Docker image, but an OCI blob mirror). Out of scope for FG-072.

7. **Out of scope**:
   - **Migrating `hc` INTO Forge as a from-source Zig build** — that's the next FG (tentatively FG-073 or later). FG-072 lands the toolchain + pre-builder; hc stays at `ghcr.io/bboortz/hc:0.1.0` (consumer unchanged).
   - **Migrating `healthy-scratch-trixie` to build hc from source** — follows the hc migration above.
   - **Node.js-style multiple Zig major versions on one builder** — Zig pins one minor; bump via chore commit.
   - **Adding bun / tigerbeetle / other Zig-based tools** — each is its own FG.
   - **`base/zig-scratch-base`** — explicitly NOT planned (Zig produces fully static binaries, same as Go).
   - **Changing cosign identity / verification URL** — FG-072 inherits the standard forge pipeline.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `build.zig-slim-base` — Forge-rooted Zig toolchain slim pre-builder. FROMs `debian-slim-trixie` (forge pre-builder) + installs Zig from ziglang.org tarball + apt-upgrade + ca-certificates + dumb-init. Sits in `publish-pre-builders` tier. Consumed by `forge-builder-zig-trixie` (dogfood).
   - NEW `build.shared-zig-builder` — `ghcr.io/bboortz/forge-builder-zig-trixie:0.1`. FROMs `zig-slim-trixie` + apt-upgrade + CA + syft (via `mirror/syft`) + git + curl + jq. Mirrors FG-046's `build.shared-go-builder` shape. Daily cron rebuilds this first (publish-builders tier) so Zig-stdlib CVE fixes land within 24h via derivative rebuilds (once a Zig consumer exists).
   - EXT `build.pre-builder-tier` — 7 members now (adds `zig-slim-trixie`).
   - EXT `image.forge-rooted-slim-bases` — Zig family added. `_EXPECTED` stays 6 (Zig's pre-builder FROMs debian-slim-trixie via ARG-indirect, not literal — doesn't trip drift grep).
   - EXT `arch.language-family-image-pair` — 4 satisfying families now (Python, Go, Node, Zig). Documented in the memory doc.

## Gherkin acceptance

```
Scenario: images/zig-slim-trixie/ exists with the pre-builder shape
  Given current HEAD
  Then images/zig-slim-trixie/Dockerfile, image.yaml, PROMISES.yaml,
       scan-baseline.json, sid-pins/, and tests/smoke_*.sh all exist
  And Dockerfile FROMs ${DEBIAN_SLIM_REF} (not debian:trixie-slim directly)
  And Dockerfile installs Zig from ziglang.org via curl + minisign verify + tar
  And Dockerfile applies apt-get upgrade + ca-certificates + dumb-init

Scenario: zig binary is present + reports a version
  Given forge-local/zig-slim-trixie:latest built
  When `docker run --rm --entrypoint=zig forge-local/zig-slim-trixie:latest version` runs
  Then output starts with "0." (pre-1.0) AND matches the pinned ZIG_VERSION

Scenario: images/forge-builder-zig-trixie/ dogfoods zig-slim-trixie
  Given images/forge-builder-zig-trixie/Dockerfile at HEAD
  Then it declares ARG ZIG_SLIM_REF=ghcr.io/bboortz/zig-slim-trixie:latest
  And its top-level FROM references ${ZIG_SLIM_REF}
  And it does NOT reference debian:trixie-slim or debian-slim-trixie directly
  And it COPYs syft from ${SYFT_REF} (mirror/syft)

Scenario: image.yaml declares depends_on
  Given images/zig-slim-trixie/image.yaml at HEAD
  Then it contains depends_on: [debian-slim-trixie]
  Given images/forge-builder-zig-trixie/image.yaml at HEAD
  Then it contains depends_on: [zig-slim-trixie, mirror/syft]

Scenario: discover-images.sh pre-builders mode returns 7 members
  Given scripts/discover-images.sh pre-builders
  Then the matrix has 7 entries including zig-slim-trixie
  And builders mode has 4 entries including forge-builder-zig-trixie

Scenario: verify-no-upstream-drift stays at _EXPECTED=6
  Given scripts/verify-no-upstream-drift.sh
  Then it exits 0 AND _EXPECTED is unchanged (6) — zig-slim-trixie uses
       ARG-indirect FROM ${DEBIAN_SLIM_REF} which doesn't match the literal grep

Scenario: arch.language-family-image-pair holds for Zig
  Given scripts/verify-dockerfile-conformance.py Rule 7 + 8 enforced
  Then forge-builder-zig-trixie's last FROM resolves to zig-slim-trixie
  And no literal `FROM debian:trixie-slim` or similar upstream in the two Zig Dockerfiles

Scenario: downstream smoke suite runs green (no current consumers, but regression guard)
  Given all images rebuilt against the new Zig pair
  When every existing acceptance + smoke test runs
  Then every test exits 0 — FG-072 introduces zero regression in Python/Go/Node fleet

Scenario: dep graph shows the new Zig edges after `make dep-graph`
  Given the regenerated docs/image-dependency-graph.md
  Then the mermaid block contains:
      `debian-slim-trixie --> zig-slim-trixie` (solid, L1 → L1 — chain-only, no intra-tier concern since zig is a distinct pre-builder)
      `zig-slim-trixie --> forge-builder-zig-trixie` (solid, L1 → L2)
      `mirror/syft -.-> forge-builder-zig-trixie` (dashed, L0.5 → L2)
  And it does NOT contain:
      any `debian:trixie-slim → zig-slim-trixie` direct upstream edge
      any `zig:X-trixie → *` direct upstream edge (Zig has no such image)

Scenario: memory + capabilities updated to list Zig as the 4th satisfying family
  Given memory/design-decisions.md § "Language family image pairs"
  Then a Zig row exists in the satisfying-families table
  And memory/docker-standard.md chain-depth example lists Zig alongside Python + Go at the 5-hop cap
  And docs/CAPABILITIES.md contains sections for build.zig-slim-base + build.shared-zig-builder
```

## References

- Plan: `docs/plan/FG-072-forge-builder-zig-trixie-plan.md` (follow-up)
- Red test: `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` (follow-up)
- Pattern precedent: FG-065 (close dedicated-toolchain exemption; introduced `go-slim-trixie` as the first zero-consumer pre-builder) + FG-061 (`node-slim-trixie`).
- Downstream motivators (not FG-072 scope; separate FGs):
  - **`hc` migration into Forge** — move `bboortz/hc` from external repo into `images/hc/` (or `images/source/hc/` post-tier-migration), build from Zig source using `forge-builder-zig-trixie`. Downstream `COPY --from=hc /hc /hc` references stay valid.
  - **`healthy-scratch-trixie` from-source build** — once hc is forge-native, healthy's builder stage builds the hc binary from source instead of COPY-from.
- Related invariants:
  - `arch.language-family-image-pair` (FG-065) — 4 satisfying families post-FG-072.
  - `arch.forge-mirror-image` (FG-066) — unaffected; Zig's upstream is a tarball, not a Docker image.
  - Chain-depth ≤ 5 — Zig chain is exactly 5 hops (one deeper than Python/Go/Node due to debian-slim-trixie intermediate).
- Tier model: Zig images land at flat paths (`images/zig-slim-trixie/`, `images/forge-builder-zig-trixie/`) today. Once FG-070 + FG-071 migrate the pre-builder + builder tiers to nested paths, Zig moves atomically along with the others (`images/pre-builder/zig-slim-trixie/`, `images/builder/zig-trixie/` — see `docs/plan/tier-layering-model.md`).
