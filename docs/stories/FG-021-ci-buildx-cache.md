---
id: FG-021
slug: ci-buildx-cache
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-021 — Docker buildx layer cache via GHCR registry

Every GHA CI job starts on a fresh runner → no docker layer cache → every image rebuilds cold → ~60s per image × 8 = ~6 min of docker-build work per full-check. Typical PRs don't change Dockerfiles; rebuilding from scratch is pure waste.

Switch `scripts/build-image.sh` from `docker build` to `docker buildx build --load` with `--cache-from=type=registry` + `--cache-to=type=registry,mode=max` pointing at a per-image `ghcr.io/bboortz/<image>:buildcache` tag. Push-to-dev + nightly cron push the cache; PR jobs read-only.

### Expected win

- 1-image-change PR: full-check ~9 min → ~3-4 min
- No-Dockerfile-change PR: full-check ~9 min → ~2-3 min
- Nightly cron: cache invalidates when upstream base-image digest changes (daily); rebuilds from cache if unchanged
- Fork PRs: no cache (no GHCR auth); fall back to cold rebuild — acceptable

## 9 canonical answers (compressed)

1. **Who** — all CI jobs; developers waiting on PR CI.
2. **When** — every PR, every push-to-dev, every nightly.
3. **Success looks like** —
   - `scripts/build-image.sh` honors `BUILDX_CACHE_FROM` + `BUILDX_CACHE_TO` env vars.
   - `.github/workflows/{ci,build,nightly}.yml` wire buildx + GHCR login + env vars.
   - PR job pulls cache (no write perm needed).
   - push-to-dev + nightly populate cache (`mode=max` stores intermediate layers).
   - Measured: typical PR's full-check CI drops from ~9 min → 2-4 min.
4. **Urgency** — quality-of-life/throughput. High visibility to devs.
5. **Happy path** —
   1. `scripts/build-image.sh` constructs `BUILDX_ARGS` from env vars; switches to `docker buildx build --load` when either cache var is set.
   2. `.github/workflows/ci.yml` full-check job: `docker/setup-buildx-action@v3` + conditional `docker/login-action@v3` for GHCR + env vars for `BUILDX_CACHE_FROM` (always) and `BUILDX_CACHE_TO` (only on push, not pull_request).
   3. `.github/workflows/build.yml` daily cron: same, `cache-to` always on (trusted event).
   4. `.github/workflows/nightly.yml`: cache-from only; the nightly's whole point is a clean-cache audit anyway.
6. **Edge cases / failure modes** —
   - `:buildcache` tag doesn't exist yet (first run): buildx silently skips cache-from; cache-to creates it. Self-bootstrap.
   - Upstream base digest changes (daily Debian updates): cache invalidates at `FROM`; cascade rebuilds. Correct behavior.
   - Fork PRs can't auth to GHCR: `docker/login-action` continues on error; buildx skips cache. Fork PR gets cold build (same as today).
7. **Out of scope** —
   - Shared forge-builder-trixie image (FG-023).
   - Local developer caching (would need `make tools` or similar; devs can opt in via env vars manually for now).
   - PR-specific cache namespacing — all PRs share the per-image `:buildcache` tag; minor contention under high PR traffic, acceptable at current volume.
8. **How we know it's done** — FG-021 acceptance green + measured CI wall-clock drop on a follow-up no-code PR.
9. **Capabilities**:
   - NEW `tooling.ci-build-cache` — GHCR-backed buildx layer cache keyed per image
   - EXT `build.pr-ci` — PR gate now cache-accelerated

## Gherkin acceptance

```
Scenario: build-image.sh honors BUILDX_CACHE_FROM env
  Given BUILDX_CACHE_FROM is set
  When scripts/build-image.sh runs
  Then it invokes docker buildx build --cache-from=<var>

Scenario: build-image.sh honors BUILDX_CACHE_TO env
  Given BUILDX_CACHE_TO is set
  When scripts/build-image.sh runs
  Then it invokes docker buildx build --cache-to=<var>

Scenario: build-image.sh falls back to plain docker build
  Given neither BUILDX_CACHE_FROM nor BUILDX_CACHE_TO is set
  When scripts/build-image.sh runs
  Then it invokes docker build (no buildx)

Scenario: ci.yml wires buildx setup + GHCR login + env vars
  Given .github/workflows/ci.yml
  Then the full-check job sets up buildx
   And logs into ghcr.io on non-fork events
   And sets BUILDX_CACHE_FROM to ghcr.io/<repo>/<image>:buildcache
   And sets BUILDX_CACHE_TO only on push events (not PRs)
```

## References

- Plan: [`docs/plan/FG-021-ci-buildx-cache-plan.md`](../plan/FG-021-ci-buildx-cache-plan.md)
- Red test: [`tests/acceptance/test_FG_021_ci-buildx-cache.sh`](../../tests/acceptance/test_FG_021_ci-buildx-cache.sh)
- Pairs with: FG-022 (grype DB cache) — shipped in the same PR
