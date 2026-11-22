# FG-090 — Plan: affected-only acceptance matrix on CI

**Story**: [`docs/stories/FG-090-affected-only-ci.md`](../stories/FG-090-affected-only-ci.md) — mirrors shepherd-side [SH-022](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-022-forge-affected-only.md).
**Status**: in-progress
**Branch**: `feat/FG-090-affected-only-ci`

## Design delta

Two changes:

**New `scripts/discover-affected-tests.sh`** (~120 lines bash). Calls `scripts/smart-check.sh --dry-run` and parses the `DISPATCH=` line it emits:

- `DISPATCH=full …` → emit `discover-tests.sh` output (84 cells).
- `DISPATCH=test-fast-only` → emit `{"include":[]}` — empty matrix.
- `DISPATCH=scoped … images=<list>` → emit matrix for tests that `grep`-match any affected image name (flat + nested token both) PLUS framework tests (any test file that doesn't reference `images/` at all — repo-wide invariants).

Any unexpected dispatch line defaults to full matrix. No test is ever silently skipped.

**`.github/workflows/ci.yml`** changes:

- `discover` job: on `pull_request` call `discover-affected-tests.sh`; on `push` to dev keep `discover-tests.sh` (full matrix safety net).
- `discover` job: install `python3-yaml` + `jq` so `smart-check.sh` + `affected_images.py` can run.
- `discover` job: `fetch-depth: 0` so `git diff origin/dev...HEAD` resolves.
- `acceptance-aggregate`: treat `skipped` matrix result as success (docs-only case). Previously `skipped` would fail the gate.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| New script separate from smart-check | smart-check already has the affected-images logic + fanout + bailout rules battle-tested. Reusing its dry-run output is a 20-line wrapper vs. 200-line duplication. |
| Always emit full matrix with `include-if` filters | GHA matrix cells are allocated before condition eval — zero wall-clock win. Must scope at matrix generation. |
| Scope `test-fast` / `lint-verify` jobs too | They're already fast (~45s). Zero win; added risk of missing a regression. |
| Delete nightly check-strict now that CI scopes | Nightly IS the safety net. Without it, "scoped was wrong about the affected set" has no backstop. |

## Breaking changes

- [ ] No. PRs that currently pass on 84 cells will still pass (fewer cells, same assertions). PRs that touch tooling / baseline / docs still get the right coverage via the three dispatch branches.

## Merge plan

- `check-smart` (pre-push, FG-017) still runs full locally.
- CI gate: this PR's own CI run validates the scoped path works on a PR to dev (since this PR touches no images, it should emit `test-fast-only` → empty matrix). Expected: lint-verify passes, acceptance-matrix skipped, acceptance-aggregate green.

## Rollout plan

Merge to `dev`. First PR landing after this gets the scoped behavior automatically. Measure PR median wall-clock over the next 5-10 PRs.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| `discover-affected-tests.sh` exists + executable | `scripts/discover-affected-tests.sh` | ✅ |
| Scoped matrix tested locally on nginx-scratch-trixie touch | 1-image touch yielded 21 cells (down from 84) | ✅ |
| Full-run bailout tested (touch scripts/smart-check.sh) | emitted full 84-cell matrix | ✅ |
| Empty matrix on no-diff / test-fast-only | observed on this branch (no image touches) | ✅ |
| `acceptance-aggregate` treats skipped as success | ci.yml updated | ✅ |
| CAP `ci.affected-only-matrix` added to CAPABILITIES.md | pending | ⚠️ |
| Post-merge PR median drops from 11.8 min baseline | measurable after a week of PRs | ⚠️ (deferred) |
