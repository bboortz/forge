---
id: FG-018
slug: ci-uses-smart-check
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-018 — CI PR uses smart-check (reuse FG-017 for faster PR feedback)

Swap `.github/workflows/ci.yml`'s **PR** gate from `make check` (~9 min, full cold-cache rebuild of every image) to `make check-smart` — reusing the FG-017 affected-image scope logic that already runs pre-push locally. Push-to-dev still runs full `make check` (dev is the stable base; no scope misjudgment risk there). Nightly cron (`.github/workflows/nightly.yml`, added in FG-017) keeps running full `check-strict` on `dev` HEAD as the safety net.

**Escape hatch**: a PR carrying the `full-check` label forces `make check-strict` (nuclear path) — for cross-cutting PRs where the dev wants extra confidence beyond smart-check's dispatch.

### What changes

- `.github/workflows/ci.yml` full-check job:
  - `fetch-depth: 0` on `actions/checkout` (smart-check needs `git diff origin/dev..HEAD`).
  - Branch: on PR → smart-check (or `check-strict` with label); on push-to-dev → `check` unchanged.
- Nothing else. FG-017's `scripts/smart-check.sh` already respects `GITHUB_BASE_REF` and dispatches correctly in a CI environment.

### Expected win

- 1-image PR: ~2-3 min (was ~9 min CI).
- 3-image PR: ~4-5 min.
- Bailout PRs (`scripts/`, `Makefile`, `.github/workflows/`, `scratch-base`, >4 images): ~9 min — same as today.
- Dev push: unchanged (~9 min, the safety-net path).

### Why now

FG-017 shipped; two data points already confirm the gate dispatches correctly:
- **FG-017's own PR**: bailout (touched `scripts/` + `Makefile`) → 14 min pre-push — the full-check path, correct.
- **FG-017 chore PR**: docs-only → test-fast-only → <1 min pre-push — the scoped path, correct.

Shipping FG-018 now unblocks CI speedup before FG-019 (scan-regression gate) lands on top — scan-regression naturally scopes to smart-check's affected set, saving grype runs on every unaffected image.

## 9 canonical answers (compressed — surgical delta)

1. **Who** — Forge maintainers waiting on CI; everyone else sees faster PR feedback.
2. **When** — every PR to `dev`.
3. **Success** — CI PR job runs `make check-smart` (or `make check-strict` if label `full-check` is set); push-to-dev still runs `make check`; nightly keeps full coverage.
4. **Urgency** — quality-of-life; medium.
5. **Happy path** — one workflow edit + one acceptance test replay confirming `make check-smart` with `GITHUB_BASE_REF=dev` dispatches as expected.
6. **Edge cases / failure modes** —
   - PR with no commits vs dev base (should never happen but handle): BASE resolution falls back via FG-017's ladder.
   - Fork PRs: `fetch-depth: 0` still works; `origin/dev` is fetched normally.
   - Label removed mid-PR run: current run uses the label state at job-start; re-run picks up the change. Documented.
7. **Out of scope** —
   - Scan-regression gate (FG-019).
   - Replacing push-to-dev's full gate with smart-check (that's the stable baseline — leave untouched).
   - Matrix-parallelism per-image (future, separate FG).
8. **Done** — FG-018 acceptance test green + workflow passes a real PR cycle.
9. **Capabilities**:
   - EXT `tooling.smart-check` — now also the PR-CI gate, not just pre-push
   - EXT `build.pr-ci` — PR CI uses the scope-aware gate

## Gherkin acceptance

```
Scenario: PR CI job uses check-smart by default
  Given .github/workflows/ci.yml full-check job
  Then the "run gate" step calls `make check-smart` on pull_request events

Scenario: full-check label forces check-strict
  Given a PR carries the "full-check" label
  Then CI runs `make check-strict` instead

Scenario: push-to-dev stays full check
  Given a push to dev
  Then CI runs `make check` (unchanged — the safety-net path)

Scenario: GITHUB_BASE_REF is honored by smart-check
  Given smart-check runs under GITHUB_BASE_REF=dev
  Then it dispatches based on `git diff origin/dev..HEAD`
```

## References

- Plan: [`docs/plan/FG-018-ci-uses-smart-check-plan.md`](../plan/FG-018-ci-uses-smart-check-plan.md)
- Red test: [`tests/acceptance/test_FG_018_ci-uses-smart-check.sh`](../../tests/acceptance/test_FG_018_ci-uses-smart-check.sh)
- Prior art: FG-017 (smart-check mechanism) + `.github/workflows/nightly.yml` (safety net)
