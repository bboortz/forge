---
id: FG-023
slug: smart-rebuild-skip
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-023 — Stamp-based rebuild skip (FG-017 Part D)

A single `make check-smart` run fires 49 `docker build` invocations for only ~6 unique images because each acceptance test rebuilds its target from cold. On a fresh CI runner the buildx cache (FG-021) helps if the `:buildcache` tag is populated, but within a single run, we're still rebuilding the same image repeatedly. Expected savings: 300-400s per full-check (measured in `docs/plan/FG-021-ci-buildx-cache-plan.md` post-ship analysis).

Introduce a stamp file per image at `.make/stamps/<image>.stamp` whose content is a digest of (local image dir + resolved upstream FROM digest + baseline image ID + resolved external SHA). `scripts/build-image.sh` checks the stamp before building; if the stamp matches current inputs AND `docker image inspect` finds the tag, skip `docker build` and reuse the daemon image. Otherwise: build, then write the new stamp.

## 9 canonical answers

1. **Who** — Forge maintainer waiting for `make check-smart` + CI engineer watching the full-check job. Downstream consumers are unaffected (stamp-skip only elides redundant local builds; published digests remain daily-rebuilt via build.yml).

2. **When** — Any time `scripts/build-image.sh` is invoked, which fires inside acceptance tests, `make build`, and transitively the pre-push gate. Each invocation first asks "has anything that affects this image changed since the last successful build on this runner?" If no → skip.

3. **What success looks like** — Within a single `make check-smart` run, each unique image gets built AT MOST once. Cross-run (local dev) stamps persist in `.make/stamps/` so a second invocation of `make check-smart` without source edits skips all builds entirely. CI observes the intra-run dedup on fresh runners (49→6 builds expected).

4. **Urgency** — Quality-of-life for maintainer, cost-of-time for CI. Measured 300-400s/run of pure rebuild waste. Not security-critical; the daily `build.yml` cron is the authoritative publisher and stamp-skip is bypassed there.

5. **Happy path**:
   1. CI full-check starts; `.make/stamps/` empty.
   2. Test A rebuilds image X → writes `.make/stamps/X.stamp`.
   3. Test B needs image X → stamp matches, image in daemon → skip build.
   4. Test C edits `images/X/Dockerfile` (hypothetical) → stamp differs → rebuild + overwrite stamp.

6. **Edge cases / failure modes**:
   - **Upstream base image moved** (e.g., `python:3.13-slim-trixie` tag re-pushed). Mitigation: stamp input includes `docker buildx imagetools inspect <FROM-ref>` digest, resolved fresh each call. Tag-mutation → new digest → stamp miss → rebuild.
   - **Externally-sourced image** (FG-012). Stamp includes resolved upstream git SHA; `ref: latest` re-resolves daily, which flips the stamp. Backstop: daily `build.yml` cron ignores stamps.
   - **Scratch derivative + baseline rebuilt** (FG-005 chain). Stamp includes baseline image ID (`docker image inspect <baseline> --format {{.Id}}`). Baseline rebuild → new ID → derivative stamp invalidates.
   - **Stamp file corrupted / partially written**. Treated as miss (safe fallback to build).
   - **Manual `docker rmi forge-local/<image>`**. Stamp exists but image gone → `docker image inspect` fails → stamp miss → rebuild.

7. **Out of scope**:
   - Skipping scan + smoke + grype — those still run against the (possibly reused) image. Stamp-skip ONLY elides `docker build`.
   - Multi-arch (amd64-only in V1; `TARGETPLATFORM` not in stamp).
   - Pre-compiled artifact caching (e.g., pip wheels). That's a Dockerfile-level concern.
   - Overriding `build.yml` daily cron behavior.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.stamp-skip` — `scripts/build-image.sh` skips `docker build` when the resolved stamp for the image matches a prior build and the tag exists in the local daemon.
   - EXT `tooling.ci-build-cache` — adds a complementary intra-run layer on top of FG-021's inter-run buildx cache.
   - EXT `tooling.smart-check` (FG-017) — `make check-strict` also wipes `.make/stamps/` before running so the strict path is unaffected by stamp-skip.

## Gherkin acceptance

```
Scenario: Stamp-skip avoids redundant rebuilds within a single check-smart run
  Given a fresh runner with empty .make/stamps/
  When make check-smart runs
  Then scripts/build-image.sh is invoked ≥ 1 time per unique image
   And subsequent invocations for the same image see a stamp hit
   And the number of actual docker-build shells is ≤ number of unique images

Scenario: Stamp invalidates on Dockerfile change
  Given .make/stamps/python-scratch-trixie.stamp exists from a prior build
  When images/python-scratch-trixie/Dockerfile is edited
  Then the next build-image.sh invocation computes a new stamp
   And docker build is actually executed (not skipped)

Scenario: Stamp invalidates on upstream FROM digest change
  Given .make/stamps/scratch-base-trixie.stamp exists
  When the upstream python:3.13-slim-trixie tag resolves to a new digest
  Then the stamp content changes
   And docker build is actually executed

Scenario: Stamp invalidates when baseline image ID changes
  Given .make/stamps/python-scratch-trixie.stamp exists against baseline ID X
  When scratch-base-trixie is rebuilt producing a new image ID Y
  Then python-scratch-trixie's stamp miss triggers rebuild

Scenario: make check-strict bypasses stamps
  Given .make/stamps/ is populated
  When make check-strict runs
  Then .make/stamps/ is wiped before the check
   And every image rebuilds cold

Scenario: FORGE_NO_SKIP=1 bypasses stamps
  Given .make/stamps/ is populated
  When FORGE_NO_SKIP=1 scripts/build-image.sh <image> runs
  Then docker build is executed regardless of stamp state
```

## References

- Plan: `docs/plan/FG-023-smart-rebuild-skip-plan.md`
- Red test: `tests/acceptance/test_FG_023_smart-rebuild-skip.sh`
- Capabilities: see `docs/CAPABILITIES.md`
