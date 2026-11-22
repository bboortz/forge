# Spec: `docs/` directory structure

**Status**: active · adopted by [FG-086](../stories/FG-086-docs-structure.md) · 2026-11-22

Every document under `docs/` lives in **exactly one** of three subdirectories.
The subdirectory encodes the document's purpose; top-level `docs/` holds no
files directly.

## The three subdirectories

### `docs/specs/` — canonical rules + contracts

Durable, authoritative docs that outlive any single FG. The "source of truth"
layer under both plans and stories.

**Members**:

| File | Role |
|------|------|
| `CAPABILITIES.md` | Capability matrix; bidirectional links to acceptance tests. |
| `LAYERING.md` | 7-tier layering model — human-readable narrative. |
| `baseline-contract.md` | `base/scratch-trixie` public contract. |
| `differentiators.md` | Forge's positioning + measurable claims vs. Chainguard/Alpine/Wolfi. |
| `tier-layering-model.md` | Detailed layering decisions + migration history (FG-067→FG-071). |
| `image-dependency-graph.md` | Auto-generated Mermaid graph. **Do not hand-edit.** Regenerate with `make dep-graph`. |
| `image-dependency-graph.svg` | Auto-generated SVG render of the Mermaid graph. **Do not hand-edit.** |
| `docs-structure.md` | This file. |

Adding a spec is unrestricted (any topic-named `.md`). Removing / renaming an
existing spec requires an FG with a pre-ship audit of every ref in the repo.

### `docs/plan/` — per-change plans

FG-scoped, time-boxed implementation plans.

**Allowed files**:

- `FG-NNN-<slug>-plan.md` — one per shipped/in-flight FG.
- `IDEAS.md` — backlog of ideas not yet promoted to stories.
- `_template.md` — canonical plan template.

Any file outside these patterns fails `scripts/verify-docs-structure.sh`.

### `docs/stories/` — consumer/maintainer stories

The 9-canonical-questions-driven user stories (see `_9-questions.md`).

**Allowed files**:

- `FG-NNN-<slug>.md` — one per shipped/in-flight FG.
- `INDEX.md` — status board; grep-friendly one-liner per story.
- `_template.md` — canonical story template.
- `_9-questions.md` — the clarification question set.

Any file outside these patterns fails `scripts/verify-docs-structure.sh`.

## What is NOT allowed

- `.md` or other files **directly under `docs/`** (no stray top-level files).
- A 4th sibling to `{specs, plan, stories}/` (no `docs/notes/`, `docs/generated/`, `docs/archive/`, etc.).
- `docs/plan/<not-matching-the-pattern>` or `docs/stories/<not-matching-the-pattern>`.

## Historical references

Shipped `docs/plan/FG-*-plan.md` and `docs/stories/FG-*.md` are **frozen-in-time
records** of each FG's state at ship time. They may reference pre-FG-086 doc
paths (e.g. `docs/CAPABILITIES.md`). That is intentional — they describe the
world as it was at that FG. The `verify-docs-structure.sh` gate skips them.

## Enforcement

Two tests enforce this spec:

1. `scripts/verify-docs-structure.sh` — wired into `make test-fast` and PR CI.
   - Walks `docs/` and asserts the allowed-file-set per subdir.
   - Greps every **active** (non-historical) file for pre-FG-086 doc paths; any match fails.
2. `tests/acceptance/test_FG_086_docs-structure.sh` — one-shot assertion of the layout + exhaustive ref sweep post-move.

## Reference migration policy

When a spec in `docs/specs/` is renamed or merged into another:
1. Update every active ref in one PR.
2. Historical `docs/plan/FG-*-plan.md` + `docs/stories/FG-*.md` stay untouched.
3. The old path **may not** be allowlisted in `verify-docs-structure.sh` — stale
   refs must be fixed in the same PR, not grandfathered.

## See also

- Story: [`../stories/FG-086-docs-structure.md`](../stories/FG-086-docs-structure.md)
- Plan: [`../plan/FG-086-docs-structure-plan.md`](../plan/FG-086-docs-structure-plan.md)
- CAPs: [`CAPABILITIES.md`](CAPABILITIES.md) `docs.three-folder-structure`, `docs.no-stale-refs-gate`
