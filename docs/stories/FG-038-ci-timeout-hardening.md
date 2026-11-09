---
id: FG-038
slug: ci-timeout-hardening
status: draft
owner: bboortz
created: 2026-11-09
---

# FG-038 — CI timeout hardening

Forge's four GHA workflows (`ci.yml`, `build.yml`, `release.yml`, `nightly.yml`) have **zero** `timeout-minutes` declarations across all twelve jobs. When a step hangs — observed 2026-11-09 on PR #66's post-merge `dev CI` run where `FG-011` stuck on the `Cache grype DB` step for 20+ minutes (job 129110343041 of run 42602539732) — GHA applies its 6-hour default. A single hung matrix cell blocks the `acceptance-aggregate` branch-protection gate for hours, delays the release.yml dispatch, and delays the daily cron.

FG-038 caps every job's wall clock with a conservative `timeout-minutes` and adds step-level timeouts + `continue-on-error: true` on the two known-flaky steps (`Cache grype DB` via `actions/cache@v4`, `Install supply-chain tools` via Docker Hub pulls). Hung steps now fail fast with a visible red signal instead of silent 6-hour stalls.

## 9 canonical answers

1. **Who** — Forge maintainer (me) blocked on CI; any PR author watching their merge window slip. Secondary: any consumer waiting for the next `:latest` cron publish that's gated on `main` moving.

2. **When** — fires every time a GHA step hangs beyond its "normal" duration. Observed triggers: GHA cache service transient slowness; Docker Hub rate-limit backoffs; registry endpoint 5xx flaps.

3. **What success looks like**:
   - Every job in `.github/workflows/*.yml` carries an explicit `timeout-minutes`.
   - `Cache grype DB` steps carry `continue-on-error: true` + `timeout-minutes: 3` — stuck cache no longer blocks the job.
   - `Install supply-chain tools` steps carry `timeout-minutes: 5`.
   - A hypothetical hanging job gets killed within its budget + 1 min and surfaces as a red check, allowing the user to retry or merge-with-label.
   - Typical PR CI total time unchanged (~2-5 min) — timeouts are ceilings, not floors.

4. **Urgency** — correctness + operator cost. The hang blocks release pipeline for hours of elapsed time; operator either waits or hand-cancels the job via GHA UI. One recurrence per week at 20 minutes each is ~17 hours of pipeline latency per year that this fix eliminates.

5. **Happy path**:
   1. Merge FG-038 to `dev`.
   2. Next CI run picks up the new `timeout-minutes` ceilings.
   3. If GHA cache hangs again on FG-NNN, the job is killed at the per-step cap (3 min) or job cap (6 min); acceptance-aggregate fails fast; operator retries the single matrix cell via GHA re-run.
   4. No more 20-minute+ hangs blocking the pipeline.

6. **Edge cases / failure modes**:
   - **Timeouts set too tight** — a job that legitimately takes 7 min on a slow runner fails with the 6-min acceptance-matrix cap. Mitigation: ceilings sized at ~2× worst-case typical for long jobs. acceptance-matrix typical is 1-3 min → 6 min cap gives 2× headroom. Short jobs (<1 min typical) stay at 5 min because of GHA runner setup floor (~30-60s).
   - **`nightly.yml check-strict` legitimately takes ~20-25 min** — full cold rebuild. Cap at 50 min (2× worst case).
   - **Cache `continue-on-error: true` masks genuine cache corruption** — mitigation: grype re-downloads DB on cache miss, so the next step logs "grype DB downloading" instead of "using cache" — visible in the log, not silent.
   - **GHA's own `timeout-minutes` enforcement delay** — GHA kills a step within ~1 min of the cap, not instantly. Acceptable.

7. **Out of scope**:
   - Retry logic for flaky steps (GHA has native `uses: nick-fields/retry@…` but adds complexity; a clean timeout + rerun is simpler).
   - Alerting (no slack/email integration in Forge today; user watches PR checks manually).
   - Replacing `actions/cache@v4` with a self-hosted cache — infrastructure cost not justified.
   - Changing retry policy on `install-tool-from-docker.sh` (already has 3 attempts + capped backoff; shell-level).
   - Adding concurrency-group cancellation — orthogonal; different failure mode.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `ci.timeout-hardened` — every job in every workflow carries an explicit `timeout-minutes`; cache + tool-install steps carry `continue-on-error: true` + short step timeouts so transient infra issues fail fast instead of hanging the pipeline.

## Gherkin acceptance

```
Scenario: every job in every workflow carries an explicit timeout-minutes
  Given each file in .github/workflows/*.yml
  When the workflow YAML is parsed
  Then every top-level job under `jobs:` has a `timeout-minutes` key
   And the value is a positive integer ≤ 60 (hard sanity cap)

Scenario: Cache grype DB is non-blocking
  Given any job that uses `actions/cache@v4` with grype-DB cache key
  Then the step carries `continue-on-error: true`
   And the step carries a `timeout-minutes` ≤ 5

Scenario: Install supply-chain tools has a short timeout
  Given any job named "Install supply-chain tools"
  Then the step carries `timeout-minutes` ≤ 10

Scenario: acceptance-matrix cap fits the typical FG job
  Given .github/workflows/ci.yml
  Then the acceptance-matrix job has `timeout-minutes` ≤ 15
   And the value is ≥ 5 (room for the slowest scratch build)

Scenario: nightly check-strict cap accommodates full cold rebuild
  Given .github/workflows/nightly.yml
  Then the check-strict job has `timeout-minutes` ≤ 60
   And the value is ≥ 30 (room for 20-25 min typical + headroom)

Scenario: No regression in CI run time
  Given a typical PR triggering ci.yml
  When CI completes successfully
  Then the total wall-clock is within 2× the pre-FG-038 baseline
   (timeouts are ceilings, not floors)
```

## References

- Plan: `docs/plan/FG-038-ci-timeout-hardening-plan.md`
- Red test: `tests/acceptance/test_FG_038_ci-timeout-hardening.sh`
- Capabilities: `docs/CAPABILITIES.md` (NEW `ci.timeout-hardened`)
- Trigger: hang observed in https://github.com/bboortz/forge/actions/runs/42602539732/job/129110343041 (FG-011 stuck on Cache grype DB for 20+ min).
