# FG-072 — Plan: Zig language-family image pair (`zig-slim-trixie` + `forge-builder-zig-trixie`)

**Story**: [`docs/stories/FG-072-forge-builder-zig-trixie.md`](../stories/FG-072-forge-builder-zig-trixie.md)
**Status**: in-progress
**Branch**: `feat/FG-072-forge-builder-zig-trixie`

## Design delta

Two new images land as a sibling pair, extending the FG-065 `arch.language-family-image-pair` invariant from 3 → 4 satisfying language families (Python, Go, Node, **Zig**).

- `images/zig-slim-trixie/` — forge-rooted Zig toolchain slim pre-builder. **FROMs `${DEBIAN_SLIM_REF}`** (not Docker Hub directly) and installs Zig from the official ziglang.org tarball with SHA256 verification. Zero consumers today; justification is the pair invariant + the FBZ dogfood.
- `images/forge-builder-zig-trixie/` — forge-rooted Zig toolchain builder. FROMs `${ZIG_SLIM_REF}` (dogfood) + `COPY --from=${SYFT_REF}` for the forge-signed syft (FG-066 mirror). Adds `git + curl + jq` for release resolution. Zero consumers today; wires in ahead of the first Zig source build (hc migration — separate FG).

Chain depth stays at the 5-hop cap:
`debian:trixie-slim → debian-slim-trixie → zig-slim-trixie → forge-builder-zig-trixie → (optional scratch runtime)`.

`_EXPECTED` in `scripts/verify-no-upstream-drift.sh` stays at **6** — zig-slim-trixie's FROM is ARG-indirect (`${DEBIAN_SLIM_REF}`), so the literal-upstream grep doesn't match it. The upstream anchor it consumes (`debian:trixie-slim`) is still owned by exactly one pre-builder (debian-slim-trixie).

## Alternatives rejected

- **FROM `debian:trixie-slim` directly in zig-slim-trixie** — would break FG-042: `debian:trixie-slim` would gain a second literal forge consumer. Rejected: one more Dockerfile to audit per CVE bump. Chaining through debian-slim-trixie preserves the single-consumer rule.
- **FROM `alpine` or `FROM scratch + zig static`** — breaks the Debian trixie foundation (`memory/design-decisions.md`). Zig produces fully static binaries but its toolchain still wants a working libc at build time (the pre-builder is a builder base, not a runtime).
- **No pre-builder; builder FROMs `debian-slim-trixie` directly** — violates FG-065 `arch.language-family-image-pair` invariant. All other language families ship both tiers.
- **Pre-build Zig itself from source** — Zig is self-hosted (`zig build` requires an existing Zig). Bootstrap would require tracking the "zig1.c" bootstrap compiler. Out of proportion to the win. We trust the ziglang.org tarball + verify SHA256; cosign-sign the result.
- **Latest-floating Zig tarball** — Zig is pre-1.0, ABI changes between minors. Pin `ZIG_VERSION=0.14.1` + commit `ZIG_SHA256`. Bump via chore commits after validating against every downstream.
- **minisign tarball verification** — the story mentions it as a strong option; deferred to a follow-up chore. Minisign isn't in Debian trixie (would need a sid pin or binary pull — more surface area). SHA256-pin + HTTPS-to-ziglang.org is the V1 compromise. Follow-up FG can add minisign once a consumer asks or a trust-chain audit demands it.

## Breaking changes

**None.** The pair introduces two zero-consumer images. Existing images, PROMISES, EXPECTATIONS, verify commands, and tag names are untouched. Pre-builder count + builder count grow by 1 each — the fleet gains two new published repos.

## Merge plan

Must pass to merge to `dev`:

- `make test-fast` (lint + `verify-dockerfile-conformance.py` with new `_PRE_BUILDERS` + `_FORGE_BUILDERS` + `_KNOWN_REF_ARGS` sets + `arch.language-family-image-pair` check seeing the new sibling pair)
- `scripts/verify-no-upstream-drift.sh` (unchanged `_EXPECTED=6`)
- `make test-acceptance` (the new `test_FG_072_forge-builder-zig-trixie.sh` goes green + no existing acceptance test regresses)
- `make dep-graph` (regenerate `docs/image-dependency-graph.{md,svg}` — expect two new L1 + L2 nodes + edges)
- `make check` (full suite — lint, traceability, acceptance, smokes for the two new images)

No gates waived.

## Rollout plan

Default path: PR → `dev` → `main` (release.yml fast-forward) → 03:00 UTC daily cron picks up the two new images + publishes to GHCR.

- First publish: `ghcr.io/bboortz/zig-slim-trixie:latest` + `ghcr.io/bboortz/forge-builder-zig-trixie:0.1`.
- Zero consumer impact at publish time. First downstream migration (hc → forge-native Zig build) is a separate FG.

## Shipping evidence

Filled at pre-ship audit (step 6a).

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: images/zig-slim-trixie/ exists with pre-builder shape | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §1 | ✅ |
| Scenario: zig binary present + reports version | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §2 | ✅ |
| Scenario: forge-builder-zig-trixie dogfoods zig-slim-trixie | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §3 | ✅ |
| Scenario: image.yaml declares depends_on | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §4 | ✅ |
| Scenario: discover-images.sh pre-builders mode returns 7 members | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §5 | ✅ |
| Scenario: verify-no-upstream-drift stays at _EXPECTED=6 | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §6 | ✅ |
| Scenario: arch.language-family-image-pair holds for Zig | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §7 | ✅ |
| Scenario: downstream smoke suite runs green | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §8 | ✅ |
| Scenario: dep graph shows new Zig edges | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §9 | ✅ |
| Scenario: memory + capabilities updated | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` §10 | ✅ |
| CAP `build.zig-slim-base` | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` + `docs/CAPABILITIES.md#buildzig-slim-base` | ✅ |
| CAP `build.shared-zig-builder` | `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh` + `docs/CAPABILITIES.md#buildshared-zig-builder` | ✅ |
| CAP `build.pre-builder-tier` (extended) | `docs/CAPABILITIES.md#buildpre-builder-tier` | ✅ |
| CAP `image.forge-rooted-slim-bases` (extended) | `docs/CAPABILITIES.md#imageforge-rooted-slim-bases` | ✅ |
| CAP `arch.language-family-image-pair` (extended — 4 families) | `docs/CAPABILITIES.md#archlanguage-family-image-pair` | ✅ |
