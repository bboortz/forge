---
id: FG-090
slug: affected-only-ci
status: in-progress
owner: @benni
created: 2026-11-22
---

# FG-090 — Affected-only acceptance matrix on CI (SH-022 win)

Umbrella: shepherd [SH-022](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-022-forge-affected-only.md) ("biggest expected single win" per the dev-cycle doc, 2026-11-22). Forge's CI PR median is 11.8 min (SH-026 baseline capture); target ≤ 5 min.

Mechanism: reuse `scripts/smart-check.sh` (already live in the pre-push hook) to decide `full` / `test-fast-only` / `scoped` on each PR, and emit a matching GHA matrix.

## 9 canonical answers

1. **Who** — every contributor opening a PR to forge/dev. Today: 84 matrix cells → 11.8 min median. After: handful of cells for most PRs (one image change ≈ 20 cells).
2. **When** — every `pull_request` targeting dev (and `push` to dev — but dev keeps the full matrix as a safety net).
3. **What success looks like** — PR median wall-clock drops substantially; nightly check-strict stays as the full-cold safety net.
4. **Urgency** — biggest measurable win in the fleet.
5. **Happy path** — scoped PR (1 image touched) → ~20 cells → ~3-4 min.
6. **Edge cases** — baseline/tooling file touched → full 84-cell matrix (safety); docs-only → empty matrix + lint-verify covers framework; no diff → empty matrix.
7. **Out of scope** — promote-by-digest (separate follow-up); affected-only for `smoke`/`build` (those are already `make test-fast`-scoped).
8. **How we know it's done** — `.github/workflows/ci.yml` `discover` job calls `discover-affected-tests.sh` on PRs; post-merge PR timing drops from 11.8 min median.
9. **Capabilities delivered or extended**:
   - NEW `ci.affected-only-matrix` — PR acceptance matrix scoped by `scripts/affected_images.py` affected set (via `smart-check.sh`); full matrix on dev-push + nightly as safety net.

## Gherkin acceptance

```gherkin
Scenario: scoped matrix on a 1-image diff
  Given a PR touching only images/nginx-scratch-trixie/Dockerfile
  When  `scripts/discover-affected-tests.sh` runs
  Then  the emitted matrix has ≥ 1 and < 84 cells
  And   the cells include tests referencing "nginx-scratch-trixie" OR framework tests

Scenario: full matrix on tooling-file touch
  Given a PR that modifies scripts/smart-check.sh or scripts/discover-tests.sh
  When  `scripts/discover-affected-tests.sh` runs
  Then  the emitted matrix equals discover-tests.sh output (84 cells)

Scenario: empty matrix on docs-only diff
  Given a PR touching only files under docs/
  When  `scripts/discover-affected-tests.sh` runs
  Then  the emitted matrix is `{"include":[]}`
  And   the acceptance-aggregate job treats `skipped` result as success

Scenario: dev-push always full matrix
  Given a push to dev (not a PR)
  Then  `ci.yml discover` calls `scripts/discover-tests.sh` (full matrix)
  And   no scoping happens
```

## Plan doc

[`docs/plan/FG-090-affected-only-ci-plan.md`](../plan/FG-090-affected-only-ci-plan.md).
