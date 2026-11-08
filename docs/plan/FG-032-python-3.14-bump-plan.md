# FG-032 — Plan: Python 3.13 → 3.14 in-place bump

**Story**: [`docs/stories/FG-032-python-3.14-bump.md`](../stories/FG-032-python-3.14-bump.md)
**Status**: shipped
**Branch**: `feat/FG-032-python-3.14-bump`

## Design delta

### `images/python-slim-trixie/`

- `image.yaml`: `tag: "3.13"` → `"3.14"`.
- `Dockerfile`: `FROM python:3.13-slim-trixie` → `FROM python:3.14-slim-trixie`. Also replaces `LABEL org.opencontainers.image.description` text that mentions 3.13.
- `scan-baseline.json`: regenerated against the new `:3.14` build.
- `PROMISES.yaml`: `version: "0.1"` → `"0.2"`; update promise descriptions that cite 3.13.

### `images/python-scratch-trixie/`

- `image.yaml`: `tag: "3.13"` → `"3.14"`.
- `Dockerfile`:
  - New `ARG PYTHON_VERSION=3.14` at the top. Default hoisted here so a future 3.15 bump is a one-line change.
  - Builder stage FROMs `forge-builder-trixie` (which transitively needs Python 3.14 — see below).
  - All `/usr/local/{bin,lib}/python3.13` COPY paths → `/usr/local/{bin,lib}/python${PYTHON_VERSION}` (dockerfile ARG substitution).
  - stdlib C-extension dep list (libutil / librt / libbz2 / liblzma / libzstd / libexpat / libffi / libsqlite3 / libnsl / libtirpc) stays identical — Python 3.14 doesn't change the stdlib dep closure. If 3.14 adds / drops a dep, the FG-003 import smoke catches it immediately.
  - FG-011 librt.so.1 stub stays in the overlay list (manylinux2014 ABI compat).
  - FG-020 SBOM embed stays (syft runs in the builder stage).
  - FG-031 `/hc` COPY stays untouched.
- `scan-baseline.json`: regenerated.
- `PROMISES.yaml`: `version: "0.3"` → `"0.4"`; update promise descriptions.

### `images/forge-builder-trixie/`

- `Dockerfile`: `ARG DEBIAN_BASE=python:3.13-slim-trixie` (default) → `python:3.14-slim-trixie`. The forge-builder's apt-upgrade / syft layer is version-agnostic; only the base tag moves.
- `image.yaml` tag stays `0.1` (builder's own version is independent of the Python version it carries).
- `PROMISES.yaml` version bump 0.1 → 0.2 if any promise text cites 3.13.
- scan-baseline.json regenerated.

### Smokes

Per-image smokes carrying `3.13` literals (e.g. in `smoke_imports.sh`, `smoke_librt_manylinux.sh`, `smoke_pip_runtime_install.sh`, `smoke_user_nonroot.sh`) switch to `3.14`. The acceptance tests for FG-003 / FG-009 / FG-011 / FG-020 / FG-031 re-run against the 3.14 images and must stay green — regression guard.

### Acceptance test

`tests/acceptance/test_FG_032_python-3.14-bump.sh` with 6 sections:
1. Static invariants — both `image.yaml` tag = "3.14"; Dockerfile `FROM python:3.14-slim-trixie` (slim) + `ARG PYTHON_VERSION=3.14` (scratch).
2. Build both images via `scripts/build-image.sh`.
3. `python3 --version` reports 3.14 inside both runtimes.
4. All downstream acceptance tests still pass: FG-003 (scratch runtime), FG-009 (nonroot), FG-011 (librt), FG-020 (SBOM), FG-031 (/hc).
5. Scan baseline has been regenerated — diff vs. committed `scan-baseline.json` is empty (no drift in-PR).
6. image.yaml tag "3.14" + no `depends_on` surprises.

### No workflow changes

`build.yml`'s discover job emits the same matrix (repo names unchanged). `ci.yml` / `release.yml` untouched.

## Alternatives rejected

- **Publish `python-scratch-trixie-3.14` as a parallel repo** — multi-version support is on the IDEAS backlog but out of scope here. Keeps repo names stable (FG-004 convention); consumers pinning `:3.13` need to migrate manually.
- **Build CPython 3.14 from source on `debian:trixie-slim`** — full control over build flags, but we take on backport cadence maintenance. Docker Hub's `python:3.14-slim-trixie` is signed by Docker Official Images and rebuilt continuously; no reason to replicate that pipeline.
- **Keep `:3.13` on a 90-day deprecation parallel-rebuild window** — consumer-friendly, but doubles the python CI cost + makes "which tag is authoritative" ambiguous. Frozen-in-place with a documented freeze date is cleaner.
- **Inline `3.14` throughout the Dockerfile** — chose ARG parameterization instead. Future 3.15 bump becomes a one-line `ARG PYTHON_VERSION=3.15` change with the rest of the Dockerfile untouched. Matches the FG-025 pattern of hoisting versions.
- **Drop the librt.so.1 stub for 3.14** — Python 3.14 itself doesn't need it (glibc 2.34+ baseline), but manylinux2014 / manylinux_2_17 wheels (numpy, scipy, pandas, pillow, cryptography) still carry `NEEDED librt.so.1`. Dropping the stub regresses FG-011.

## Breaking changes

- **Consumers hardcoding `/usr/local/lib/python3.13/...`** break on next `:latest` cron. Documented consumer path: either pin `:3.13` (frozen, no new CVE patches) or update COPY paths to `/usr/local/lib/python3.14/...`.
- **beaconry-hub + beaconry-scout** are the only known internal-ecosystem consumers hitting this. Fix lands in a separate PR against `bboortz/beaconry` BEFORE forge's `release.yml` promotion.
- **`python-slim-trixie` consumers running `apt install python3=<pinned-3.13-version>`** — not supported; our contract is "latest patched python at the Debian major we track".
- **No change** to the public verify command, GHCR repo names, attestation format, cosign identity, or FG-031 `/hc` presence.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass.
- FG-032 acceptance test green.
- Full acceptance sweep green (FG-003, FG-009, FG-011, FG-020, FG-031 all re-run against 3.14).
- `scan-baseline.json` committed for both images.
- README `§ Images` table updated to "Python 3.14" (preserves the public tag reference).
- Merge order:
  1. `feat/FG-032-python-3.14-bump` → `dev` (this PR).
  2. Open beaconry companion PR on `bboortz/beaconry` — fixes hardcoded `/install/lib/python3.13/...` paths. Merge to beaconry main.
  3. `release.yml` promotes forge `dev` → `main`.
  4. Next 03:00 UTC cron publishes `python-scratch-trixie:3.14` + `python-slim-trixie:3.14` as `:latest`. Beaconry's next cron rebuilds against the new `:latest` with its 3.14-aware recipe.

## Rollout plan

- **Day 0**: forge PR merged to dev. No consumer impact (dev isn't published).
- **Day 0 same session**: beaconry companion PR opened + merged.
- **Day 0 or Day 1**: forge release.yml dispatch.
- **Day 1, 03:00 UTC**: cron publishes python-scratch-trixie:3.14 + python-slim-trixie:3.14 as :latest. Beaconry cron rebuilds successfully.
- **Day 1+**: consumers pinned to `:latest` start pulling 3.14 on their next pull. Consumers pinned to `:3.13` continue with the frozen last-3.13 build.
- **Day 90**: review `:3.13` tag usage. If no measurable pull activity, consider pruning from GHCR in a separate chore story.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: :3.14 publishes with standard triple | `tests/acceptance/test_FG_032_python-3.14-bump.sh` § 1-2 | ⏳ |
| Scenario: python3 reports 3.14 | § 3 | ⏳ |
| Scenario: slim keeps shell + apt | § 3 | ⏳ |
| Scenario: FG-009 nonroot contract preserved | § 4 (re-runs test_FG_009) | ⏳ |
| Scenario: FG-011 librt / manylinux preserved | § 4 (re-runs test_FG_011) | ⏳ |
| Scenario: FG-031 /hc still embedded | § 4 (re-runs test_FG_031) | ⏳ |
| Scenario: scan-baseline carries 3.14 closure | § 5 + committed `scan-baseline.json` | ⏳ |
| Scenario: beaconry companion PR lands before main-promotion | rollout plan step 2; tracked in beaconry repo | ⏳ |
| EXT `image.python-scratch-nonroot` | `docs/CAPABILITIES.md#image.python-scratch-nonroot` | ⏳ |
| EXT `image.manylinux-wheel-compat` | `docs/CAPABILITIES.md#image.manylinux-wheel-compat` | ⏳ |
| EXT `image.ssl-cert-env` | re-asserted via FG-009 re-run | ⏳ |
| EXT `build.two-stage-scratch` | re-asserted via test_FG_003 re-run | ⏳ |
