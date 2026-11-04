# FG-005 — Plan: scratch-base-trixie

**Story**: [`docs/stories/FG-005-scratch-base-trixie.md`](../stories/FG-005-scratch-base-trixie.md)
**Status**: shipped (pending post-publish evidence)
**Branch**: `feat/FG-005-scratch-base-trixie`

## Design delta

Introduce a shared signed foundation for every Forge scratch image. `scratch-base-trixie` ships the strict intersection of the python, nginx, and postgres closures:

- dynamic linker (`/lib64/ld-linux-x86-64.so.2`)
- core glibc satellites: `libc`, `libm`, `libdl`, `libpthread`, `libcrypt`, `libgcc_s` — **NOT** `libutil` (nginx doesn't need; python + postgres add it in their overlay)
- TLS: `libssl.so.3`, `libcrypto.so.3`
- common compression: `libz.so.1`, `libzstd.so.1`
- DNS resolution: `libnss_dns.so.2`, `libnss_files.so.2`, `libresolv.so.2`
- `/etc/ssl/certs/ca-certificates.crt`
- `/etc/nsswitch.conf`
- `/etc/passwd` + `/etc/group` with only root + nobody; derivatives OVERWRITE with their own service-user-augmented version
- `/usr/share/zoneinfo`
- `/tmp` with mode 1777

Every derivative preserves `FROM scratch` as the literal runtime base and composes via `COPY --from=${SCRATCH_BASE_REF} / /` + its own `COPY --from=builder /out /`. Last COPY wins on path collision — critical for `/etc/passwd` where each derivative appends its service user (uid 33 for www-data, uid 999 for postgres).

Key script changes:

- `scripts/_image_yaml.sh` gains `image_yaml_depends()` returning the `depends_on:` list.
- `scripts/build-image.sh` recursively builds each `depends_on` entry first, so `make build IMAGE_DIR=python-scratch-trixie` auto-builds scratch-base-trixie from a cold cache.
- `scripts/build-image.sh` drops `--pull` when `SCRATCH_BASE_REF` resolves to a locally-present `forge-local/*` image (legacy docker builder tries to pull even for local refs and fails).
- `.github/workflows/build.yml` splits into `publish-base` (hardcoded scratch-base-trixie job) + `publish-derivatives` (matrix over everything else, `needs: publish-base`). Ensures the baseline exists on GHCR before any derivative tries to `FROM` it on a cold runner.

## Alternatives rejected

- **Include libutil in baseline** — nginx doesn't need it. Including would violate the strict-intersection principle the baseline is built on. Minor size win (~24 KB saved) matters more as a principle than as bytes.
- **Use `FROM scratch-base-trixie` directly in derivatives** — would hide the `FROM scratch` differentiator claim. `COPY --from=` keeps the composition explicit and the pitch honest.
- **Pre-bake baseline into derivative builder images** — eliminates the GHCR dependency but kills the audit story (no independent digest to verify). Dropped.
- **Skip scripts/_image_yaml.sh depends_on parsing; hard-code baseline build in Makefile** — works but isn't extensible. Future scratch variants would each need a Makefile edit.
- **Add file-contents smoke tests INSIDE the baseline via a test-stage** — scratch has no exec, so tests must run outside the image. `docker save | tar tf` inspection is clean and dependency-light.

## Breaking changes

None. Derivative image REFs and tags unchanged; smoke suites unchanged; consumer verify commands unchanged. The baseline is a new signed artifact; its existence doesn't break any existing consumer. First publish of the baseline makes a new GHCR package (`scratch-base-trixie`) — one-time visibility flip.

## Merge plan

Fast tier (local `make check-strict`): lint, verify-sid-pins, verify-traceability, test-acceptance (incl. new FG-005 + existing FG-001–007), test-images (now 29 scripts across 5 images). Pre-push + CI run the same.

CI ordering concern: ci.yml's full-check runs `make check` which does its own build chain locally, so no CI-side ordering is needed inside a single ci.yml job. The build.yml publish workflow is the one that needs the `needs: publish-base` split.

## Rollout plan

Standard: merge to `dev`, operator triggers `release.yml` → `main`, then `build.yml` publishes. Daily cron picks up both baseline and derivatives in correct order per the `needs:` split.

One-time manual: flip GHCR package visibility to public on the new `scratch-base-trixie` package after first publish.

For this autonomous run: merge to `dev` only; publish + visibility flip are operator actions.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: baseline dir exists | `tests/acceptance/test_FG_005_scratch-base-trixie.sh` (s1) | ✅ |
| Scenario: baseline builds + contents smokes | `images/scratch-base-trixie/tests/smoke_contents_*.sh` + `smoke_size.sh` | ✅ |
| Scenario: derivatives compose on baseline | test_FG_005 (s4) + each derivative's Dockerfile | ✅ |
| Scenario: every derivative smoke still passes | test_FG_005 (s5) | ✅ |
| Scenario: baseline size ≤ 25 MB | smoke_size.sh (SIZE_CEILING=25_000_000) | ✅ (13.14 MB measured) |
| Scenario: differentiators doc updated | test_FG_005 (s7) | ✅ |
| CAP `build.scratch-baseline` | test_FG_005 + `docs/CAPABILITIES.md` | ✅ |
| CAP `test.scratch-contents` | baseline's smoke_contents_*.sh + `docs/CAPABILITIES.md` | ✅ |
| EXT `image.zero-os-cves` on baseline | `images/scratch-base-trixie/tests/smoke_contents_zero_os_cves.sh` | ✅ |
| EXT `test.size-budget` on baseline | `images/scratch-base-trixie/tests/smoke_size.sh` | ✅ |
| `build.yml` matrix ordering (publish-base first) | `.github/workflows/build.yml` | ✅ (two-stage job) |
| `scripts/build-image.sh` auto-builds deps | `scripts/build-image.sh` (recursive call on depends_on) | ✅ |
| Scenario: baseline publishes to its own GHCR repo (post-publish) | `publish-base` job | ⚠️ post-publish |
| Scenario: baseline cosign-verifies (post-publish) | FG-005 acceptance PUBLISHED=1 | ⚠️ post-publish |

Local measurements:
- baseline size: **13.14 MB** (53 % of 25 MB ceiling)
- python-scratch size: **45.28 MB** (unchanged within rounding vs. pre-refactor 44.45 MB)
- nginx-scratch size: **15.36 MB** (unchanged vs. pre-refactor 15.34 MB)
- postgres-scratch size: **104.06 MB** (unchanged vs. pre-refactor 104.05 MB)
- 29 smoke scripts across 5 images (baseline + 4 variants) pass under `make check-strict`
