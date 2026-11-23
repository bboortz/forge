# FG-091 — Plan: adopt shepherd SH-042 hook-commit / hook-push tiers

**Story**: [`docs/stories/FG-091-hook-tiers.md`](../stories/FG-091-hook-tiers.md) — mirrors the shepherd-side [SH-042](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-042-hook-tiers.md)
**Status**: ready
**Branch**: `feat/SH-042-hook-tiers`

## Design delta

Forge already owns the right step targets (`lint`, `verify-sid-pins`, `verify-traceability`, `check-smart`). SH-042 just adds the fleet-canonical tier *names* on top:

- `COMMIT_STEPS ?= lint verify-sid-pins verify-traceability` — commit-tier contents (~15 s).
- `PUSH_STEPS   ?= check-smart` — push-tier contents (~2 min, already FG-017 scope-aware).
- `hook-commit: $(COMMIT_STEPS)` and `hook-push: $(PUSH_STEPS)` — one-line wrappers.
- `.PHONY: … hook-commit hook-push` — declared alongside the existing suite.

Zero changes to step targets, scripts, workflows, or `.shepherd.yml`. Pure addition.

## Alternatives rejected

- **Make `hook-push = check-smart-strict` (the full per-image docker wipe)** — slower than the 2-minute budget allows on cold caches; `check-smart` is the pre-push gate already enforced by the local git hook, so hook-push mirrors it.
- **Rename `check-smart` → `test-affected`** — forge's native name carries FG-017 context; SH-042 explicitly keeps step names repo-native and only aligns the tier names. SH-044 is where any cross-fleet step-level convergence lives.
- **Fold `verify-contracts` / `verify-image-dirs` / `verify-no-upstream-drift` into `COMMIT_STEPS`** — those run fine in `test-fast` on push; adding them to the ~15 s commit budget risks blowing it on cold caches. Keep commit tier minimal; push tier (via check-smart → test-fast) still catches them.

## Breaking changes

None. New public targets; no existing target renamed or removed.

## Merge plan

1. `make -n hook-commit` + `make -n hook-push` parse cleanly (unit check via acceptance test §2).
2. `bash tests/acceptance/test_FG_091_hook-tiers.sh` green locally.
3. `make test-fast` green — picks up the new test via the glob in `ACCEPTANCE_TESTS`, plus traceability covers the two new CAPs.
4. PR → `dev` → merge (default auto-merge).

No `check-strict` regression — recipe unchanged; only new targets added.

## Rollout plan

Merge to `dev`. Forge contributors + agents can immediately use `make hook-commit` / `make hook-push`. Local pre-commit / pre-push hooks continue to invoke their current targets — a follow-up chore can migrate the hook scripts to call the new tier names, but is explicitly out of scope here.

## Shipping evidence

| Gherkin scenario | Test assertion | Status |
|---|---|---|
| `.PHONY` declares hook-commit + hook-push | Section 1 | ✅ |
| hook-commit dry-run invokes commit steps | Section 3 | ✅ |
| hook-push dry-run invokes check-smart | Section 4 | ✅ |
| CAPs registered + linked | Section 6 + `verify-traceability` | ✅ |
| Story + plan docs exist | Section 5 | ✅ |
| INDEX lists FG-091 | Section 7 | ✅ |

Three lenses:

- **Gherkin coverage**: each scenario pinned to a test section. ✅
- **Behaviour symmetry**: shepherd ships the same shape (`COMMIT_STEPS` + `PUSH_STEPS` + wrappers + `.PHONY` + acceptance test); forge's test file mirrors shepherd's `test_SH_042_hook_tiers.sh` with forge-native expectations. ✅
- **Self-consistency**: no workflow edits, no step renames, no §12-protected files touched. `make test-fast` still exercises verify-traceability which now covers the two new CAPs. ✅
