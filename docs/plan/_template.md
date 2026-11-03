# FG-NNN — Plan: <one-line title>

**Story**: [`docs/stories/FG-NNN-<slug>.md`](../stories/FG-NNN-<slug>.md)
**Status**: draft → ready → shipped
**Branch**: `feat/FG-NNN-<slug>`

## Design delta

What changes, and why. One paragraph per design decision.

## Alternatives rejected

- **<alternative>** — why we're not doing it.
- **<alternative>** — why we're not doing it.

## Breaking changes

Does this change the public verify command, consumer pull reference, tag naming, or attestation format? If no, say "None". If yes, list them and the migration path.

## Merge plan

Which gates must pass before this can merge to `dev`. Reference `memory/workflow.md § Blocking gates` for the full matrix; call out any gate that is temporarily waived (and why).

## Rollout plan

How this gets to consumers after merge. Default path: `dev` → `main` (CI fast-forward) → next 03:00 UTC cron. For urgent changes: `workflow_dispatch` immediately after merge.

## Shipping evidence

Filled at pre-ship audit (step 6a). One row per Gherkin scenario + one per CAP delivered. ✅ means a concrete pointer exists; ⚠️ / ❌ blocks shipping.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: <name> | `tests/acceptance/test_FG_NNN_<slug>.sh:<line>` | ⚠️ |
| CAP `<cap.id>` | `tests/acceptance/test_FG_NNN_<slug>.sh:<line>` + `docs/CAPABILITIES.md#<cap.id>` | ⚠️ |
