---
id: FG-024
slug: parallel-acceptance
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-024 — Parallel acceptance-test matrix in CI

22 acceptance tests currently run sequentially on CI as part of `make check-smart`. Even with FG-021 (buildx cache) + FG-023 (stamp-skip) landed, CI wall-clock for full-check is ~5-6 min — bounded by the sequential sum of per-test times. Converting the acceptance suite into a GHA matrix (one job per test file) replaces "sum of all tests" with "max of any test," expected drop to ~2-3 min wall-clock.

Local `make check` + `make check-smart` keep running tests sequentially (FG-023 made that fast enough locally — matrix adds job-orchestration noise without local benefit).

## 9 canonical answers

1. **Who** — Maintainer waiting for PR green; CI engineer watching usage/minutes. Downstream consumers unaffected.

2. **When** — PR events targeting `dev` + push-to-`dev`. Fast-check (lint) stays a separate always-run job.

3. **What success looks like** — PR full-check wall-clock halves (~6 min → 2-3 min) with the same test coverage. Each acceptance test is a separate GHA job visible in the Checks tab. A single `acceptance-all-green` gate aggregates them for required-status purposes.

4. **Urgency** — Quality-of-life. Not security-critical; every test still runs per PR.

5. **Happy path**:
   1. PR opens → `fast-check` (lint, 30s), `acceptance-aggregate` (needs matrix) start.
   2. `acceptance-matrix` fans out: 22 parallel jobs, each runs ONE test with full setup (buildx + GHCR auth + grype DB cache + tool install + _FORGE_IN_CHECK=1 run).
   3. All 22 jobs complete in ~2-3 min wall-clock.
   4. `acceptance-aggregate` goes green; PR mergeable.

6. **Edge cases / failure modes**:
   - **Fork PR has no GHCR access** — buildx cache misses; test still runs (just rebuilds cold). Existing `continue-on-error: true` on GHCR login preserves this.
   - **Flaky test** — matrix job re-runnable individually without re-running the full suite.
   - **Matrix list drift** — new `test_FG_NNN_<slug>.sh` must appear in the matrix. Solved by `scripts/discover-tests.sh` reading `tests/acceptance/test_FG_*.sh` dynamically.
   - **CI minute cost rises** — ~22 × (per-job setup) extra minutes. Setup cost is ~45s per job → ~16 min extra billable CI/run. Trade-off: wall-clock vs minutes used. Acceptable at current volume.

7. **Out of scope**:
   - Local test parallelism (leave as-is; FG-023 made it fast enough)
   - Dynamic scoping via smart-check (PRs that change one image still run all 22 tests in parallel; acceptable given per-job stamp-skip + buildx cache)
   - Test grouping heuristics (one-job-per-file is simplest; optimizations later)

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `tooling.ci-parallel-tests` — CI runs each acceptance test as a parallel GHA matrix job
   - EXT `build.pr-ci` — PR wall-clock reduced via parallel matrix
   - EXT `tooling.ci-build-cache` — matrix jobs still consume FG-021 buildx cache + FG-022 grype DB cache per-job

## Gherkin acceptance

```
Scenario: discover-tests.sh emits a JSON matrix of all acceptance tests
  Given the tests/acceptance/ directory contains 22 test_FG_*.sh files
  When scripts/discover-tests.sh is invoked
  Then stdout is a JSON object {include: [{test: <filename>, ...}, ...]}
   And the array has one entry per discovered test
   And each entry carries test + fg_id

Scenario: ci.yml wires acceptance-matrix with matrix dispatch
  Given .github/workflows/ci.yml is parsed
  When grep matches the acceptance-matrix job
  Then the job uses strategy.matrix with include derived from discover-tests.sh
   And the job's run step invokes exactly ONE test file
   And the job has docker/setup-buildx-action + login + grype cache + tool install

Scenario: ci.yml wires acceptance-aggregate gate
  Given .github/workflows/ci.yml is parsed
  When grep matches the acceptance-aggregate job
  Then the job declares needs: [acceptance-matrix]
   And it passes iff every matrix job passed (strategy.fail-fast respected)

Scenario: full-check no longer runs acceptance tests
  Given .github/workflows/ci.yml is parsed
  When the full-check job's run step is inspected
  Then it invokes lint + verify-* only (make test-fast)
   And it does NOT invoke make check-smart / make check / make test-acceptance

Scenario: local make check-smart still runs acceptance sequentially
  Given a local dev invokes `make check-smart` (with FG-023 stamps populated)
  When the script runs
  Then test-acceptance runs sequentially as before
   And matrix behavior only applies to CI
```

## References

- Plan: `docs/plan/FG-024-parallel-acceptance-plan.md`
- Red test: `tests/acceptance/test_FG_024_parallel-acceptance.sh`
- Capabilities: see `docs/CAPABILITIES.md`
