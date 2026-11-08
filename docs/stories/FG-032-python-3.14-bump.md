---
id: FG-032
slug: python-3.14-bump
status: shipped
owner: bboortz
created: 2026-11-08
---

# FG-032 — Bump python-scratch-trixie + python-slim-trixie to Python 3.14 (in-place)

Python 3.14 shipped in October 2025. Forge still publishes `python-scratch-trixie:3.13` + `python-slim-trixie:3.13` as the latest tracked majors. FG-032 bumps both images **in place** — the GHCR repo names stay (`python-scratch-trixie`, `python-slim-trixie`), only the `tag:` in `image.yaml` moves `3.13 → 3.14`. The historical `:3.13` tag freezes on GHCR (daily cron stops rebuilding it); the new `:3.14` becomes the primary, and `:latest` floats with it.

## 9 canonical answers

1. **Who** — every consumer of either python Forge image. Internal: `beaconry-hub` + `beaconry-scout` (both `FROM ghcr.io/bboortz/python-scratch-trixie:latest` in their upstream Dockerfiles). External: operators building on `python-slim-trixie` or `python-scratch-trixie`. Forge maintainer managing the version cadence.

2. **When** — fires every time a consumer wants the current Python major without manually tracking Forge version tags. Pipeline fires on the next 03:00 UTC cron after this story lands on `main` + the beaconry companion fix is merged.

3. **What success looks like**:
   - `ghcr.io/bboortz/python-scratch-trixie:3.14` + `:latest` publish daily with the full signed/scanned/attested triple.
   - `ghcr.io/bboortz/python-slim-trixie:3.14` + `:latest` publish daily with the same triple.
   - `/usr/local/bin/python3 --version` reports Python 3.14.x inside both runtimes.
   - FG-011 librt stub still shipped; numpy / scipy / pandas / pillow / cryptography wheels still dlopen (manylinux ABI compat preserved).
   - FG-009 nonroot contract preserved (uid 65532, HOME /nonroot, ENTRYPOINT=python3, SSL_CERT_FILE re-declared).
   - scan-baseline.json regenerated in this PR — first PR CI after merge does NOT trip scan-regression with phantom "new CRITICAL" findings from the baseline flip.
   - Legacy `:3.13` tag remains fetchable from GHCR but stops moving (no new CVE patches, documented in README).

4. **Urgency** — Quality-of-life for current consumers + a hard dependency chain: beaconry's `verify_pinned_versions` lint accepts `:latest`, so the moment forge publishes 3.14 as `:latest`, beaconry's next cron fails on the hardcoded `/install/lib/python3.13/...` COPY path (beaconry CAP-1845 acknowledges this fragility). So FG-032 is coupled to a companion beaconry PR.

5. **Happy path**:
   1. Open forge PR to `dev`: bump both `image.yaml` tags, bump Dockerfile FROM, parameterize via `ARG PYTHON_VERSION=3.14`, regen scan baselines, update smokes.
   2. CI green on PR (builds against forge-local tags; beaconry CI not involved).
   3. Merge to `dev`. Do **not** promote via `release.yml` yet.
   4. Open the beaconry companion PR that either hardcodes 3.14 in the COPY paths (`/install/lib/python3.14/site-packages`) or dynamically resolves the python version from the base image. Land it on beaconry's main.
   5. Once beaconry's main carries the 3.14-compatible build recipe, promote forge dev→main via `release.yml`.
   6. Next 03:00 UTC cron publishes `python-scratch-trixie:3.14` + `python-slim-trixie:3.14` as `:latest`. On the same cron, beaconry-hub + beaconry-scout rebuild against the new `:latest` with their 3.14-aware recipe.

6. **Edge cases / failure modes**:
   - **Docker Hub `python:3.14-slim-trixie` tag resolve fails.** Docker Hub ships `python:3.14-slim-trixie` on CPython 3.14 release; if for some reason it's not yet available at implementation time, build pauses until it lands (or we pin a specific digest discovered via `docker pull python:3.14-slim-trixie`).
   - **Python 3.14 stdlib C-extension deps shift.** The current python-scratch Dockerfile COPYs a fixed list: `libutil`, `librt` (FG-011), `libbz2`, `liblzma`, `libzstd`, `libexpat`, `libffi`, `libsqlite3`, `libnsl`, `libtirpc`. If 3.14 adds / drops a stdlib dep (e.g. zoneinfo now links something new), the import smoke catches it immediately — fix the lib list and retry.
   - **manylinux wheel compat regression.** FG-011 librt stub stays. `smoke_librt_manylinux.sh` re-runs against 3.14 — mandatory gate before merge.
   - **Beaconry breakage window.** Between forge main-promotion and the beaconry main-merge, beaconry's cron fails. Mitigation: merge beaconry's companion PR **before** running forge's `release.yml` (step 5 above). If timing slips, one cron cycle (24h) of beaconry red; no operator action required to recover.
   - **scan-baseline.json drift.** 3.14 has a different Debian package closure vs. 3.13; regenerating the baseline in this PR matches the drift one-shot and avoids a transient "new CRITICAL vs. old baseline" false alarm on the first post-merge PR.

7. **Out of scope**:
   - Keeping `:3.13` on a parallel rebuild cadence. It freezes on day 1 (documented in README).
   - Shipping a `python-slim-trixie-3.13` or `-3.14` suffixed repo. Repo names are stable; version is in the tag per FG-004.
   - Multi-version support (3.13 + 3.14 in parallel). On the IDEAS backlog as "Multi-version matrix"; not this story.
   - Rebuilding Python 3.14 from source on debian:trixie-slim. Using Docker Hub's prebuilt `python:3.14-slim-trixie` is the simplest path.
   - CPython C-API changes impacting consumers (e.g. module cleanup migration): consumers own their code; Forge doesn't gate on it.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.python-scratch-nonroot` — same CAP, now at Python 3.14. CAP description updated to drop the "3.13" number (or made version-agnostic).
   - EXT `image.manylinux-wheel-compat` — same stub, verified under 3.14. Smoke re-run.
   - EXT `image.ssl-cert-env` — unchanged behavior, re-asserted.
   - EXT `build.two-stage-scratch` — unchanged pattern, applied to 3.14.
   - EXT `publish.ghcr-public-pull` — new `:3.14` tag publishable without authentication.

## Gherkin acceptance

```
Scenario: python-scratch-trixie:3.14 publishes with the standard Forge triple
  Given a successful build.yml publish cycle (after forge main is on 3.14)
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists CPython 3.14.x + Debian trixie packages
   And the grype attestation is attached
   And `:3.14` + `:latest` both point at the same digest

Scenario: /usr/local/bin/python3 reports 3.14
  Given forge-local/python-scratch-trixie:3.14 is built
  When `docker run --entrypoint=/usr/local/bin/python3 <image> --version` runs
  Then stdout matches `Python 3\.14\.[0-9]+`

Scenario: python-slim-trixie:3.14 keeps the shell and apt
  Given forge-local/python-slim-trixie:3.14 is built
  When `docker run <image> /bin/sh -c 'python3 --version'` runs
  Then stdout matches `Python 3\.14\.[0-9]+`
   And `/bin/bash` is present (shell preserved)

Scenario: FG-009 nonroot contract preserved at 3.14
  Given forge-local/python-scratch-trixie:3.14 is built
  When the FG-009 acceptance test (test_FG_009_python-scratch-hardening.sh) runs
  Then every assertion passes (uid 65532, HOME=/nonroot, ENTRYPOINT=python3, SSL_CERT_FILE declared)

Scenario: FG-011 librt / manylinux wheel compat survives
  Given forge-local/python-scratch-trixie:3.14 is built
  When `smoke_librt_manylinux.sh` runs
  Then /lib/x86_64-linux-gnu/librt.so.1 is present and dlopen-able
   And a sample manylinux2014 wheel (e.g. cryptography) imports successfully

Scenario: FG-031 /hc still embedded at 3.14
  Given forge-local/python-scratch-trixie:3.14 is built
  When the image is inspected via `docker save | tar tf`
  Then /hc is present at the image root
   And `docker run --entrypoint=/hc <image>` exits 2 (usage on no-args)

Scenario: scan-baseline carries 3.14 closure
  Given this PR is merged
  When the next PR's scan-regression gate runs
  Then it compares against the regenerated 3.14 baseline
   And does not fire on 3.13→3.14 package drift

Scenario: beaconry companion PR lands before forge main-promotion
  Given FG-032 is merged to forge dev
  When beaconry's companion PR lands on bboortz/beaconry main
   And then forge dev→main is promoted via release.yml
   And the next 03:00 UTC cron fires
  Then both forge python images publish :3.14 successfully
   And beaconry-hub + beaconry-scout rebuild against the new :latest successfully
   And no cron fails in the transition window
```

## References

- Plan: `docs/plan/FG-032-python-3.14-bump-plan.md`
- Red test: `tests/acceptance/test_FG_032_python-3.14-bump.sh`
- Capabilities: see `docs/CAPABILITIES.md` (EXT only — no new CAPs)
- Upstream base: Docker Hub `python:3.14-slim-trixie`
- Predecessors: FG-001 (python-slim), FG-003 (python-scratch), FG-009 (nonroot hardening), FG-011 (librt), FG-020 (SBOM embed), FG-031 (/hc embed)
- Downstream coupling: `bboortz/beaconry` runtime Dockerfiles — companion PR required before main-promotion
