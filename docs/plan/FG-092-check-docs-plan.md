# FG-092 — Plan: adopt shepherd SH-055 `check-docs` fleet tier

**Story**: [`docs/stories/FG-092-check-docs.md`](../stories/FG-092-check-docs.md) — mirrors the shepherd-side [SH-055](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-055-check-docs.md)
**Status**: ready
**Branch**: `feat/SH-055-check-docs`

## Design delta

Forge already owns the right drift gates (`verify-traceability`, `verify-sid-pins`, `verify-promises-version-bump`). SH-055 adds the fleet-canonical wrapper *name* on top:

- `check-docs: verify-traceability verify-sid-pins verify-promises-version-bump` — thin wrapper, no logic.
- `.PHONY: … check-docs` — declared alongside the existing suite.
- `PUSH_STEPS ?= check-docs check-smart` — wired into `hook-push` so pre-push catches drift.
- `ci-branch: lint check-docs test-affected` — CI backstop for `--no-verify` pushes.

Zero changes to the delegate scripts, step targets, workflows, or `.shepherd.yml`. Pure addition.

Note the shepherd story names `verify-promises-version` in the fleet-map table; forge's actual target is `verify-promises-version-bump` (same script, repo-native name preserved per SH-042's no-step-rename rule).

## Alternatives rejected

- **Add `check-docs` as a prerequisite of `test-fast`** — `test-fast` already includes all three delegates directly. Re-running them from a wrapper there would just be noise. The *entry-point unification* is what matters; `test-fast` + `make check` keep their native call sites.
- **Rename `verify-promises-version-bump` → `verify-promises-version`** — SH-042 explicitly keeps step names repo-native; SH-055 only unifies the wrapper name. SH-044 is where any cross-fleet step-level convergence lives.
- **Only add to `hook-push`, skip `ci-branch`** — loses the belt. A developer who skipped the hook with `--no-verify` would ship drift. CI needs to catch it too.
- **Add to `COMMIT_STEPS` / `hook-commit` instead** — the three delegates currently take under 2 s each on a clean tree, so budget isn't the issue; but `verify-traceability` reads every story + plan + test + CAP and `verify-promises-version-bump` diffs against `origin/dev`. Both scale with repo size + network. `hook-push`'s ~2 min tier is the stable home for I/O-heavier gates.
- **Fold `verify-docs-structure` / `verify-no-upstream-drift` into `check-docs`** — those are architectural rules (not doc staleness) and already run in `test-fast`. Keeping `check-docs` tight to the three drift gates makes the fleet-map predictable.

## Breaking changes

- [ ] Yes
- [x] No — strictly additive. `check-docs` is a new target; existing targets unchanged. `PUSH_STEPS` grows by one token; `ci-branch` grows by one prerequisite.

## Rollout plan

Merge to `dev`. Forge contributors + agents can immediately use `make check-docs`. Pre-push hook picks up the new `PUSH_STEPS` entry on next run; next PR triggers `ci-branch` with the new wiring. No downstream notice needed — the three delegates already ran via `test-fast`, so observable behaviour on green trees is unchanged.

## Shipping evidence

| Gherkin scenario | Test assertion | Status |
|---|---|---|
| `.PHONY` declares check-docs | Section 1 | ✅ |
| check-docs target with three prerequisites | Section 2 | ✅ |
| PUSH_STEPS + ci-branch include check-docs | Section 3 | ✅ |
| `make -n check-docs` resolves | Section 4 | ✅ |
| check-docs dry-run invokes the three delegates | Section 5 | ✅ |
| hook-push dry-run now includes check-docs' delegates | Section 6 | ✅ |
| Story + plan docs exist | Section 7 | ✅ |
| CAP registered | Section 8 + `verify-traceability` | ✅ |
| INDEX lists FG-092 | Section 9 | ✅ |

Three lenses:

- **Gherkin coverage**: each scenario pinned to a test section. ✅
- **Behaviour symmetry**: shepherd ships the same shape (`check-docs` wrapper + delegate list + `PUSH_STEPS` + `BRANCH_STEPS` + acceptance test); forge's test file mirrors shepherd's `test_SH_055_check_docs.sh` with forge-native expectations (and `ci-branch` in place of `BRANCH_STEPS` since forge's branch tier is a `make` target rather than a variable). ✅
- **Self-consistency**: no workflow edits, no step renames, no §12-protected files touched. `make test-fast` still exercises verify-traceability which now covers the new CAP. ✅
