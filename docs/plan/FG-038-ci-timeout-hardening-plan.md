# FG-038 — Plan: CI timeout hardening

**Story**: [`docs/stories/FG-038-ci-timeout-hardening.md`](../stories/FG-038-ci-timeout-hardening.md)
**Status**: draft
**Branch**: `feat/FG-038-ci-timeout-hardening`

## Design delta

### Per-job `timeout-minutes` (12 jobs across 4 workflows)

Ceilings at **~2× worst-case typical** for the long jobs. Short jobs (<1 min typical) stay at 5 min because GHA runner setup overhead (actions/checkout + login + setup-buildx) eats 30-60s before the "real" step starts — so 5 min is effectively ~2-5× of wall-clock, not 10×.

| Workflow | Job | Typical | Cap | Rationale |
|---|---|---|---|---|
| ci.yml | fast-check | 30s | 5 | floor (runner setup) |
| ci.yml | lint-verify | 45s | 5 | floor (runner setup) |
| ci.yml | discover | 10s | 5 | floor |
| ci.yml | acceptance-matrix | 1-3 min | **6** | **2× worst case** |
| ci.yml | acceptance-aggregate | 2s | 2 | floor |
| ci.yml | release-check | 10s | 5 | floor |
| build.yml | discover | 10s | 5 | floor |
| build.yml | publish-builders | 3-5 min | **10** | 2× worst case |
| build.yml | publish-base | 3-5 min | **10** | 2× worst case |
| build.yml | publish-derivatives | 5-8 min | **16** | 2× worst case |
| release.yml | promote | 30s | 5 | floor |
| nightly.yml | check-strict | 20-25 min | **50** | 2× worst case |

**acceptance-matrix (6)** is the critical one — it's where the observed hang bit. The slowest scratch image build + smoke suite runs in ~3 min; 6 min gives 2× headroom. A hang now dies within 6 min instead of 6 hours.

### Step-level timeouts on the known-flaky steps

- **`Cache grype DB`** (`actions/cache@v4`) — add `timeout-minutes: 3` + `continue-on-error: true`. Cache action normally completes in seconds; 3 min cap kills the GHA-service hang. `continue-on-error` means cache miss is a soft fail (grype downloads fresh DB, adds ~30s), not a pipeline block.
- **`Install supply-chain tools`** — add `timeout-minutes: 5`. Docker Hub pulls for syft + grype + cosign; typical 20-40s. 5 min cap catches DH rate-limit backoffs.

### No workflow-logic changes

Only annotations. No step reordering, no retry logic added. The `install-tool-from-docker.sh` script already has 3-attempt retry.

### Red acceptance test

`tests/acceptance/test_FG_038_ci-timeout-hardening.sh`:
1. **Static workflow invariants** via Python/PyYAML:
   - For each `.github/workflows/*.yml`: parse → every top-level job has `timeout-minutes` set to a positive int ≤ 60.
   - acceptance-matrix cap is between 5 and 15.
   - check-strict cap is between 30 and 60.
2. **Step-level invariants**:
   - Every step using `actions/cache@v4` for grype DB has `continue-on-error: true` AND `timeout-minutes` ≤ 5.
   - Every step named "Install supply-chain tools" has `timeout-minutes` ≤ 10.
3. **CAP registration check**: `ci.timeout-hardened` exists in `docs/CAPABILITIES.md`.

### `docs/CAPABILITIES.md`

NEW `ci.timeout-hardened` entry — describes the per-job cap matrix + step-level flaky-step handling.

## Alternatives rejected

- **Global default via `defaults:` block** — GHA doesn't support `timeout-minutes` as a job-level default; must be set per job. Per-job explicit is the right shape.
- **Native retry logic (`nick-fields/retry`)** — adds third-party dependency, masks the "hang" signal with "retry succeeded". Timeouts are cleaner — operator sees the actual failure and decides.
- **Shorter `nightly check-strict` cap** — would false-positive on legitimate 25-min runs during busy GHA capacity. 45 min accommodates.
- **Per-step timeout on every step** — overkill. Only the two network-heavy steps are observed sources of hangs.
- **Self-hosted GHA runners** — infrastructure cost not justified by this issue alone.

## Breaking changes

None. The timeouts are ceilings — any job that finishes within its typical runtime is unaffected. The only new behavior: hanging jobs now terminate at their cap and surface as red checks (previously: silent 6-hour hang).

## Merge plan

- Red test exists pre-implementation (section 1 fails). Done at story draft.
- Implementation: 12 `timeout-minutes` additions across 4 files + 2 step-level annotations in ci.yml + 1 CAP registration.
- Red test turns green.
- `make test-fast` + `make verify-traceability` + `actionlint` clean.
- `make check-smart-strict` (pre-push gate) passes.

## Rollout plan

1. Land FG-038 on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Daily cron immediately benefits — no further action needed.
4. First time a step hangs post-merge, the job gets killed within budget; operator retries the single cell via GHA re-run UI instead of waiting out a 6-hour stall.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: every job has timeout-minutes | `tests/acceptance/test_FG_038_...sh` § 1 | ⏳ |
| Scenario: Cache grype DB is non-blocking | § 2 (continue-on-error + timeout) | ⏳ |
| Scenario: Install supply-chain tools short timeout | § 2 | ⏳ |
| Scenario: acceptance-matrix cap sized | § 1 (bounds check 5-15) | ⏳ |
| Scenario: nightly check-strict cap sized | § 1 (bounds check 30-60) | ⏳ |
| Scenario: no CI runtime regression | observable post-merge (not asserted in test) | ⏳ |
| NEW CAP `ci.timeout-hardened` | `docs/CAPABILITIES.md` + acceptance test | ⏳ |
