# FG-003 — Plan: python scratch runtime + central build/test scripts

**Story**: [`docs/stories/FG-003-python-scratch-runtime.md`](../stories/FG-003-python-scratch-runtime.md)
**Status**: shipped (pending post-publish evidence)
**Branch**: `feat/FG-003-python-scratch-runtime`

## Design delta

Introduce a second python image variant — `python:3.13-scratch-trixie` — with no shell, no `apt`, no `dpkg` database, so grype against the base layer finds zero Debian-source matches. Delivers differentiator #3 (minimal attack surface).

Directory layout moves from "one image dir" to "one dir per variant":

- `images/python-slim-trixie/` (renamed from `images/python/`)
- `images/python-scratch-trixie/` (new)

Each ships an `image.yaml` metadata file that maps the on-disk directory name to the published GHCR identifier:

```yaml
# images/python-scratch-trixie/image.yaml
repo: python
tag: 3.13-scratch-trixie
platforms: [linux/amd64]
```

Both variants publish under the same `ghcr.io/bboortz/python` package with distinct tag suffixes — matches Docker Hub's convention for multi-variant single-repo images.

Central scripts replace per-image build.sh and the Makefile's inline test loop:

- `scripts/build-image.sh <image-dir>` — reads `image.yaml`, runs `docker build` with standard labels + `--pull`
- `scripts/test-images.sh [image-dir]` — globs `images/*/tests/smoke_*.sh`, sets `IMAGE_NAME` + `IMAGE_TAG` + `REGISTRY` env from each image's `image.yaml`
- `scripts/discover-images.sh` — emits a JSON `include:` matrix for `build.yml` so new image dirs auto-enroll in the publish pipeline

Scratch Dockerfile is two-stage: builder is `python:3.13-slim-trixie` (so the ldd closure matches what we're about to COPY). Runtime stage is `FROM scratch` with explicit COPY lines for interpreter + stdlib + dyn-linker + libs + CA bundle + zoneinfo + nss config + pip. pip is included in scratch — consumer can `pip install --target <dir>` a wheel at runtime; sdist installs that need gcc still don't work (that's what slim is for).

## Alternatives rejected

- **Family dir with sub-variants** (`images/python/{slim-trixie,scratch}/`) — more symmetric but adds a path level and requires nested globbing. Sibling dirs keep the Makefile and scripts flat.
- **Exclude pip from scratch** — matches Chainguard convention but forces consumers to use slim for any pip-touching use case. User explicitly asked for pip to work at runtime.
- **One Dockerfile with `--target` for both variants** — single file is harder to lint cleanly; the two Dockerfiles are structurally different enough that one file obscures rather than clarifies.
- **GHA matrix enumerated explicitly** — `[python-slim-trixie, python-scratch-trixie]` works today but every new image needs a workflow edit. Auto-discovery means `images/*/image.yaml` is the single source of truth.
- **Retire slim variant** — not in scope; slim ships pip + apt + a shell and is the right choice for builder stages or operators who need to debug.

## Breaking changes

- **`IMAGE_NAME` default changes** — the Makefile defaults for `IMAGE_NAME` + `IMAGE_TAG` no longer map directly to a directory. Users who ran `make build` with no args got `python:3.13-slim-trixie` before; now the Makefile requires an explicit `IMAGE_NAME=python-slim-trixie` (or picks the first dir — TBD during impl).
- **Per-image `build.sh` is removed.** Any external caller (CI, local tooling) that invoked `bash images/python/build.sh` directly now uses `scripts/build-image.sh python-slim-trixie`.
- **Test acceptance FG-001/FG-002** — both get updated to use `IMAGE_NAME=python-slim-trixie` (directory name) with `IMAGE_TAG` resolved from `image.yaml`. No behavioural change to what they assert.
- Consumer-visible contract is **additive**: new tag `python:3.13-scratch-trixie` joins the existing `python:3.13-slim-trixie`. Old tag + verify identity unchanged.

## Merge plan

Fast tier (local `make check`): lint, verify-sid-pins (vacuous), verify-traceability, test-acceptance (incl. FG-001/002/003), test-images (every image's suite). Pre-push runs it all.

PR CI full-check runs the same on a clean runner.

The acceptance test for FG-003 is a heavy wrapper: it builds *both* variants from scratch, runs the full smoke suite against each, exercises the scratch-specific tests (no-shell, zero-OS-CVEs, pip-runtime-install), and validates the GHA matrix discovery emits the expected JSON.

## Rollout plan

1. Merge PR to `dev` (Claude auto-merges on green CI).
2. Operator runs `release.yml` → `main` fast-forwards.
3. Operator triggers `build.yml` via `workflow_dispatch`. Matrix runs; both variants publish + sign + attest.
4. Each new GHCR package (`python` already exists public; no change required — the new tag inherits public visibility).
5. Next daily cron picks up the matrix automatically.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: slim renamed, scratch added | `tests/acceptance/test_FG_003_python-scratch-runtime.sh` (section 1) | ✅ |
| Scenario: central build script resolves image.yaml | `tests/acceptance/test_FG_003_python-scratch-runtime.sh` (section 2) | ✅ |
| Scenario: central test script runs every variant | `tests/acceptance/test_FG_003_python-scratch-runtime.sh` (section 3) | ✅ |
| Scenario: scratch image has no shell | `images/python-scratch-trixie/tests/smoke_scratch_no_shell.sh` | ✅ |
| Scenario: grype finds zero Debian matches | `images/python-scratch-trixie/tests/smoke_scratch_zero_os_cves.sh` | ✅ |
| Scenario: scratch size ≤ 60 MB | `images/python-scratch-trixie/tests/smoke_size.sh` | ✅ |
| Scenario: both variants pass common smoke suite | `images/python-*/tests/smoke_*.sh` × test runner | ✅ |
| Scenario: pip runtime install works | `images/python-*/tests/smoke_pip_runtime_install.sh` | ✅ |
| Scenario: GHA matrix auto-discovers | `scripts/discover-images.sh` + test section 4 | ✅ |
| Scenario: both variants publish side-by-side | `.github/workflows/build.yml` matrix | ⚠️ post-publish |
| CAP `build.two-stage-scratch` | `images/python-scratch-trixie/Dockerfile` | ✅ |
| CAP `image.no-shell` | `images/python-scratch-trixie/tests/smoke_scratch_no_shell.sh` | ✅ |
| CAP `image.zero-os-cves` | `images/python-scratch-trixie/tests/smoke_scratch_zero_os_cves.sh` | ✅ |
| CAP `build.central-script` | `scripts/build-image.sh` | ✅ |
| CAP `test.central-script` | `scripts/test-images.sh` | ✅ |
| CAP `publish.matrix-auto-discovery` | `scripts/discover-images.sh` + `build.yml` | ⚠️ post-publish |
| README Images + verify commands updated | `README.md` | ✅ |

Post-publish rows transition once the first matrix-driven publish succeeds.

**Local metrics**: scratch image lands at **44.45 MB** (26 % of the 60 MB ceiling, 34 % of slim's 121 MB); grype reports **2 total matches** against scratch, **0** of which are Debian-source (both are PyPI deps bundled with pip itself).
