# FG-025 — Plan: Shared forge-builder-trixie (Phase 1)

**Story**: [`docs/stories/FG-025-forge-builder-trixie.md`](../stories/FG-025-forge-builder-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-025-forge-builder-trixie`

## Design delta

### `images/forge-builder-trixie/` (new)
- `Dockerfile`: `FROM python:3.13-slim-trixie` + apt-upgrade + install ca-certificates + install syft, then remove curl.
- `image.yaml`: tag `"0.1"`, no `depends_on` (it's a leaf base).
- `PROMISES.yaml`: declares `files.syft-binary`, `files.ca-certificates`, `apt.freshly-upgraded`, `apt.no-cache`, `apt.no-curl`.
- `tests/smoke_has_syft.sh` + `tests/smoke_ca_bundle.sh`.

### `scripts/discover-images.sh`
- New mode `builders` that matches a hardcoded list `(_FORGE_BUILDERS=(forge-builder-trixie))`. Existing `base` mode excludes anything matched by `_is_builder`. `derivatives` unchanged.
- Centralized special-case keeps build.yml table-driven.

### `.github/workflows/build.yml`
- New `publish-builders` job (matrix from `discover.outputs.builders`); full publish steps (build + scan + sign + verify).
- `publish-base` gains `needs: [discover, publish-builders]` so scratch-base-trixie's cold-runner builder FROM resolves.
- `publish-derivatives` unchanged (still `needs: [discover, publish-base]`).

### `images/scratch-base-trixie/Dockerfile`
- New ARG `FORGE_BUILDER_REF` (default `forge-local/forge-builder-trixie:0.1`).
- Builder stage `FROM ${FORGE_BUILDER_REF}`.
- Removed `apt-get update + upgrade` and `curl + syft install` RUN blocks (now pre-done by forge-builder-trixie).
- Kept: sid-pins COPY (still needed for Phase 2 compatibility), syft SBOM extract RUN, and the actual `install -d /out/…` assembly.

### `scripts/build-image.sh`
- Pre-build hook: when building any scratch image (NOT python-slim-trixie, beaconry-*, or forge-builder itself), recursively build forge-builder-trixie first.
- New `FORGE_BUILDER_REF` resolution: prefer local tag, else fall back to `ghcr.io/bboortz/forge-builder-trixie:<tag>`.
- Pass `--build-arg FORGE_BUILDER_REF=...` to the docker build so derivatives inherit the correct ref.

## Alternatives rejected

- **Full-scope migration of all 4 scratch images in one PR** — bigger PR, more risk, and scratch-base dominates the matrix wall-clock anyway. Phase 2 migrates the others once Phase 1 proves stable.
- **Add `forge-builder-trixie` as a `depends_on` of every scratch image** — would move all four from `base`/`derivatives` tiers by discover-images.sh's current logic, forcing a wider refactor. The builder-FROM is a different concept than scratch COPY-from dependency.
- **Field-driven: add `builder_from:` to `image.yaml`** — more scalable, but YAGNI for one builder image. Centralizing the hardcoded list in `_FORGE_BUILDERS` is simpler.
- **Base on `debian:trixie-slim` instead of `python:3.13-slim-trixie`** — would require python-scratch's derivative to add Python back. Keeping the common base means ALL derivatives can switch in Phase 2 without adding Python.

## Breaking changes

None user-facing. CI publish ordering gains a tier; existing images unaffected.

**Branch-protection note:** No new required-check names. `publish-builders` runs on cron/dispatch only (same as the rest of build.yml); not a PR gate.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass
- FG-025 acceptance test green
- FG-005 (scratch-base acceptance) still green (regression check)
- `make test-fast` green

## Rollout plan

Lands on `dev` via standard PR flow. After merge, next scheduled `build.yml` cron publishes forge-builder-trixie as `ghcr.io/bboortz/forge-builder-trixie:0.1` + `:latest`. Daily cron continues publishing scratch-base-trixie — now built on forge-builder-trixie.

Phase 2 (deferred): a follow-up FG migrates python-scratch-trixie / nginx-scratch-trixie / postgres-scratch-trixie builder stages. Phase 2 can be shipped once Phase 1 has run through at least one daily cron cleanly.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: forge-builder-trixie is a complete image | `tests/acceptance/test_FG_025_forge-builder-trixie.sh` § 1 + § 6 | ⏳ |
| Scenario: 3-tier CI publish orders forge-builder-trixie before scratch-base-trixie | § 2 + § 5 | ⏳ |
| Scenario: scratch-base-trixie delegates builder-stage boilerplate | § 3 | ⏳ |
| Scenario: build-image.sh pre-builds forge-builder-trixie for scratch images | § 4 | ⏳ |
| CAP `build.shared-builder` | `docs/CAPABILITIES.md` + test | ⏳ |
| EXT `build.two-stage-scratch` | scratch-base's updated Dockerfile | ⏳ |
| EXT `tooling.ci-build-cache` | build.yml publish-builders tier | ⏳ |
