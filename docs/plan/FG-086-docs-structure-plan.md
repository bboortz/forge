# FG-086 — Plan: three-folder `docs/` convention

**Story**: [`docs/stories/FG-086-docs-structure.md`](../stories/FG-086-docs-structure.md)
**Spec**: [`docs/specs/docs-structure.md`](../specs/docs-structure.md)
**Status**: in-progress → shipped
**Branch**: `feat/FG-086-docs-structure`

## Design delta

Flat `docs/` → three-folder `docs/{specs,plan,stories}/`:

| From | To |
|------|-----|
| `docs/CAPABILITIES.md` | `docs/specs/CAPABILITIES.md` |
| `docs/LAYERING.md` | `docs/specs/LAYERING.md` |
| `docs/baseline-contract.md` | `docs/specs/baseline-contract.md` |
| `docs/differentiators.md` | `docs/specs/differentiators.md` |
| `docs/image-dependency-graph.md` | `docs/specs/image-dependency-graph.md` |
| `docs/image-dependency-graph.svg` | `docs/specs/image-dependency-graph.svg` |
| `docs/plan/tier-layering-model.md` | `docs/specs/tier-layering-model.md` |

New files:
- `docs/specs/docs-structure.md` — the spec itself (defines the convention + allowed-file-set per subdir).
- `scripts/verify-docs-structure.sh` — ongoing gate wired into `make test-fast`.
- `tests/acceptance/test_FG_086_docs-structure.sh` — red → green acceptance.

Deleted:
- `docs/stories/FG-073-nginx-scratch-alpine.md` — uncommitted stale draft superseded by FG-079/FG-080.

## Alternatives rejected

- **Only move the 6 top-level files; leave `tier-layering-model.md` under `plan/`** — the file self-describes as a spec (spans FG-067→FG-071, status "proposed"). Leaving it under `plan/` perpetuates the ambiguity the FG is meant to fix.
- **New `docs/generated/` subdir for the dep-graph pair** — adds a 4th subdir, contradicts the three-folder goal, and requires extra Makefile/script path edits.
- **SPEC-NN numbering, FG-tracked spec versions** — heavier convention with no concrete benefit today. Specs stay topic-named; FG-NNN diffs already give us version-of-record evolution.
- **Symlink `docs/CAPABILITIES.md -> specs/CAPABILITIES.md` for back-compat** — violates the "docs/ top-level contains only {specs,plan,stories}/" invariant. Clean cut is better.

## Breaking changes

None for consumers (nothing outside the repo references these paths). Internally:
- CI pre-commit `files:` regexes update; existing hooks keep working.
- All active tests + scripts + Makefile + memory + CLAUDE.md + README + PROMISES.yaml update atomically in this PR.
- Historical `docs/plan/FG-*-plan.md` + `docs/stories/FG-*.md` are intentionally left alone — they're frozen-in-time records of each FG's state at ship time.

## Merge plan

Full `memory/workflow.md § Blocking gates`. The critical gates:
- `make test-fast` (now includes `verify-docs-structure`).
- `make test-acceptance` — ~24 existing FG tests reference old paths and must be rewritten in this PR to continue passing.
- PR CI acceptance matrix runs the FG-086 test among others.

## Rollout plan

1. PR → dev (auto-merge on green CI).
2. `release.yml` → main.
3. No `build.yml` republish needed — this is docs/scripts only, no image rebuild.

## Tooling updates

- `scripts/verify-docs-structure.sh` — new. Asserts:
  - `docs/` top-level entries = exactly `{specs, plan, stories}/`.
  - `docs/plan/` entries match `FG-\d+-.*-plan\.md | IDEAS\.md | _template\.md`.
  - `docs/stories/` entries match `FG-\d+-.*\.md | INDEX\.md | _template\.md | _9-questions\.md`.
  - `docs/specs/` is open (any topic-named `.md` or `.svg`).
  - No active (non-historical) file references pre-FG-086 doc paths.
- `Makefile` — `test-fast` depends on `verify-docs-structure`.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: Layout after FG-086 | `tests/acceptance/test_FG_086_docs-structure.sh:§1` | ✅ |
| Scenario: No active file references old paths | `tests/acceptance/test_FG_086_docs-structure.sh:§2` | ✅ |
| Scenario: Structural gate blocks future drift | `tests/acceptance/test_FG_086_docs-structure.sh:§3` | ✅ |
| CAP `docs.three-folder-structure` | `tests/acceptance/test_FG_086_docs-structure.sh:§1` + `docs/specs/CAPABILITIES.md#docs.three-folder-structure` | ✅ |
| CAP `docs.no-stale-refs-gate` | `tests/acceptance/test_FG_086_docs-structure.sh:§2,§3` + `docs/specs/CAPABILITIES.md#docs.no-stale-refs-gate` | ✅ |
| `make test-fast` green | pre-ship | ✅ |
