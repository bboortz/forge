# FG-024 — Plan: parallel acceptance-test matrix in CI

**Story**: [`docs/stories/FG-024-parallel-acceptance.md`](../stories/FG-024-parallel-acceptance.md)
**Status**: shipped
**Branch**: `feat/FG-024-parallel-acceptance`

## Design delta

### `scripts/discover-tests.sh`

Emits a JSON matrix spec on stdout:

```json
{"include":[
  {"test":"tests/acceptance/test_FG_001_python-slim-pipeline.sh","fg_id":"FG-001"},
  {"test":"tests/acceptance/test_FG_002_python-image-smoke-suite.sh","fg_id":"FG-002"},
  ...
]}
```

Extracts fg_id from the filename (`test_FG_<NNN>_*.sh` → `FG-<NNN>`). Matrix include entries make GHA job names predictable (`acceptance (FG-NNN)`).

### `.github/workflows/ci.yml` — split full-check into two jobs

Current shape:
- `fast-check` (always on push) — lint/verify-* only
- `full-check` (PR to dev + push to dev) — full `make check-smart`
- `release-check` (push to main) — minimal

New shape:
- `fast-check` (always on push) — unchanged
- `lint-verify` (PR to dev + push to dev) — `make test-fast` + verify-* only (no acceptance)
- `discover` (PR to dev + push to dev) — emits `matrix` output via `scripts/discover-tests.sh`
- `acceptance-matrix` (PR to dev + push to dev; needs `discover`) — `strategy.matrix.include` from discover; runs one test
- `acceptance-aggregate` (PR to dev + push to dev; needs `acceptance-matrix`) — single green/red gate (makes branch protection config stable)
- `release-check` — unchanged

### Per-matrix-job steps

Identical shape to current full-check except for the final `run`:

```yaml
- name: Run ${{ matrix.fg_id }}
  env:
    _FORGE_IN_CHECK: '1'   # same dedup env check-smart uses
    FORGE_CACHE_FROM_PREFIX: ghcr.io/bboortz
    FORGE_CACHE_PUSH: ${{ github.event_name == 'push' && '1' || '0' }}
  run: bash "${{ matrix.test }}"
```

### Required-status check rename note

The GH branch-protection rule (if any) currently requires "Full check (make check)". After this change, the required check becomes "Acceptance aggregate (all green)". If a branch-protection rule exists, it needs updating when this merges. (Documented in rollout plan below.)

## Alternatives rejected

- **Local parallelism (`make -j test-acceptance`)** — reused docker daemon state fights `-j` safety; FG-023 already gave us local speed.
- **Grouped matrix by image dependency** — complex scheduling logic; one-job-per-file is simpler and still wins substantially.
- **Fan out via smart-check scope (only affected tests run)** — loses parallelism benefit for PRs that touch common infra; re-introduces scope correctness risk the FG-017 Part D safety net was designed to catch. Matrix-all is strictly safer.
- **Replace `full-check` in-place (same job name, different semantics)** — breaks branch-protection required-check list silently.

## Breaking changes

**Branch-protection required-check list** (if configured). The current "Full check (make check)" check is replaced by "Acceptance aggregate (all green)" + "Lint & verify". Any PR template or ruleset referencing the old name needs updating.

Not a breaking change for consumers (published image digests, verify commands, tags are unchanged). CI-only restructuring.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass
- `make test-fast` green
- New `tests/acceptance/test_FG_024_parallel-acceptance.sh` green (static inspection of ci.yml + discover-tests.sh)
- First post-merge PR observed as green — this is the only real validation of matrix orchestration

## Rollout plan

Lands on `dev` via standard PR flow. After merge:

1. Open a trivial follow-up PR (docs tweak) to observe actual matrix wall-clock
2. If branch-protection rule exists, update required-check names to match new job IDs
3. Daily `build.yml` cron untouched (separate workflow)

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: discover-tests.sh emits JSON matrix | `tests/acceptance/test_FG_024_parallel-acceptance.sh` § 1 | ⏳ |
| Scenario: ci.yml wires acceptance-matrix | § 2 | ⏳ |
| Scenario: ci.yml wires acceptance-aggregate | § 3 | ⏳ |
| Scenario: full-check no longer runs acceptance | § 4 (now `lint-verify`) | ⏳ |
| Scenario: local make check-smart unchanged | § 5 | ⏳ |
| CAP `tooling.ci-parallel-tests` | `docs/CAPABILITIES.md` + test | ⏳ |
| EXT `build.pr-ci` | wall-clock measurement post-merge | ⏳ |
| EXT `tooling.ci-build-cache` | matrix jobs still consume cache | ⏳ |
