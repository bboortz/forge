# FG-002 — Plan: python image smoke suite + per-image test convention

**Story**: [`docs/stories/FG-002-python-image-smoke-suite.md`](../stories/FG-002-python-image-smoke-suite.md)
**Status**: shipped
**Branch**: `feat/FG-002-python-image-smoke-suite`

## Design delta

Introduce `images/<name>/tests/` as the canonical home for image-contract tests. Pipeline-level tests remain in `tests/acceptance/`; script-helper unit tests in `tests/unit/`. Image-contract tests ("does this image actually do what it promises?") co-locate with the recipe that produces them.

For `python:3.13-slim-trixie`, six smoke scripts cover: stdlib imports, TLS context init, CA bundle presence, pip dry-run against a real wheel, entrypoint behavior, image-size budget. Each is independently runnable (`bash images/python/tests/smoke_<thing>.sh`) and all are driven by a new `make test-images` target that globs `images/*/tests/*.sh`.

The size budget uses **upstream base × 1.1** as the hard ceiling. Reusable: every image under `images/<name>/` compares its final size against the base referenced in its Dockerfile. 10% headroom accommodates `apt upgrade` deltas without masking a true regression.

## Alternatives rejected

- **Centralize under `tests/smoke/<image>/`** — orphaning risk (image deleted, tests left behind), weaker ownership signal. Co-location makes `images/<name>/` self-contained.
- **Use `bats` framework per image** — additional dep for every workstation + CI runner; plain shell with `set -euo pipefail` is sufficient and matches the rest of the project.
- **Defer to FG-003** — then FG-003 has no contract oracle. Scratch runtime without smoke tests is an unfalsifiable claim.
- **Image-size *regression* gate (compare vs. previous `:latest`)** — needs a baseline + pull mechanism; defer to a dedicated gate story. Absolute budget vs. base is the right first slice.

## Breaking changes

None. New directory + new Makefile target + new section in `memory/docker-standard.md`.

## Merge plan

Fast tier (local `make check`): lint (incl. shellcheck on every new script), verify-sid-pins (vacuous), verify-traceability, test-acceptance, **test-images** (new). PR CI runs the full tier on a fresh runner.

## Rollout plan

Standard: merge to `dev`, Claude auto-merges on green CI, user triggers `release.yml` when convenient. Published image is unchanged by this story — no `build.yml` re-run required.

## Shipping evidence

One row per Gherkin scenario + one per CAP + one for the `docker-standard.md` convention update.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: suite lives next to Dockerfile | `tests/acceptance/test_FG_002_python-image-smoke-suite.sh` (section 1) | ✅ |
| Scenario: make test-images discovery | `tests/acceptance/test_FG_002_python-image-smoke-suite.sh` (section 2) | ✅ |
| Scenario: each script independently runnable | `tests/acceptance/test_FG_002_python-image-smoke-suite.sh` (section 3) | ✅ |
| Scenario: Python core stdlib | `images/python/tests/smoke_imports.sh` | ✅ |
| Scenario: TLS context initializes | `images/python/tests/smoke_tls_handshake.sh` | ✅ |
| Scenario: CA bundle readable | `images/python/tests/smoke_ca_bundle.sh` | ✅ |
| Scenario: pip dry-run wheel | `images/python/tests/smoke_pip_install.sh` | ✅ |
| Scenario: entrypoint runs python3 | `images/python/tests/smoke_entrypoint.sh` | ✅ |
| Scenario: image size ≤ base × 1.1 | `images/python/tests/smoke_size.sh` | ✅ |
| Scenario: make check runs test-images | `Makefile` (check target) + test section 4 | ✅ |
| CAP `test.image-smoke-suite` | `images/python/tests/` + `docs/CAPABILITIES.md#test.image-smoke-suite` | ✅ |
| CAP `test.makefile-glob` | `Makefile` (test-images target) + `docs/CAPABILITIES.md#test.makefile-glob` | ✅ |
| CAP `test.size-budget` | `images/python/tests/smoke_size.sh` + `docs/CAPABILITIES.md#test.size-budget` | ✅ |
| Convention documented | `memory/docker-standard.md` § Per-image smoke tests | ✅ |

All rows ✅ — `make check` green end-to-end, 6 smoke scripts pass against `forge-local/python:3.13-slim-trixie`. Image size came in at **121.26 MB** (upstream base `python:3.13-slim-trixie` is 118.35 MB — 2.5 % headroom used out of 10 % budget).
