---
id: FG-086
slug: docs-structure
status: in-progress
owner: bboortz
created: 2026-11-22
---

# FG-086 — Three-folder `docs/` convention: specs, plan, stories

The `docs/` directory has grown organically. Six top-level `.md`/`.svg` files
(CAPABILITIES, LAYERING, baseline-contract, differentiators, image-dependency-graph.{md,svg})
sit next to the two existing `plan/` + `stories/` subdirs, and one cross-cutting spec
(`docs/plan/tier-layering-model.md`) was parked under `plan/` for want of a better home.
FG-086 formalises the layout: **every doc lives in exactly one of three subdirs**
— `docs/specs/` (canonical rules + contracts), `docs/plan/` (FG-scoped plans), or
`docs/stories/` (consumer/maintainer stories). The convention is enforced at CI
time so future drift fails fast.

## 9 canonical answers

1. **Who** — Forge maintainer navigating the repo; new contributor onboarding; Claude session reading context; tooling that globs `docs/`.
2. **When** — Every time someone adds or looks for a doc. A flat `docs/` with 6 top-level files + a cross-cutting spec hidden under `plan/` is already costing seconds-per-lookup; the next big spec would make it worse.
3. **What success looks like** —
   - `docs/` top-level contains **only** `specs/`, `plan/`, `stories/` (no stray files).
   - `docs/specs/` holds the 5 canonical specs + the 2 generated graph artifacts.
   - `docs/plan/` + `docs/stories/` keep their FG-NNN-scoped docs + templates.
   - Every active reference (scripts, Makefile, pre-commit, tests, memory, CLAUDE.md, README, PROMISES.yaml) resolves to the new path. Zero broken links.
   - A new `scripts/verify-docs-structure.sh` gate fails CI if the invariant drifts.
4. **Urgency** — Quality-of-life, ergonomic. No CVE. But every day we delay, new docs land in the wrong place; this is cheapest to ship before the next spec.
5. **Happy path** —
   1. `git mv` the 6 top-level files + `plan/tier-layering-model.md` into `docs/specs/`.
   2. Update every active reference in a single pass.
   3. Add `scripts/verify-docs-structure.sh` to `make test-fast`.
   4. Red FG-086 acceptance test proves no stale refs anywhere in the repo (except historical `docs/plan/FG-*-plan.md` + `docs/stories/FG-*.md` which are frozen-in-time snapshots).
6. **Edge cases / failure modes** —
   - **Historical FG plans/stories still mention old paths**: INTENTIONAL. Those files are historical records of the state at FG shipping time; rewriting them would falsify history. The verifier explicitly excludes `docs/plan/FG-*-plan.md` + `docs/stories/FG-*.md` from the no-stale-refs sweep.
   - **Pre-commit `files:` regex breaks**: `docs/CAPABILITIES.md` → `docs/specs/CAPABILITIES.md` in `.pre-commit-config.yaml`.
   - **Dep-graph gate**: Makefile + `mermaid-to-svg.sh` + `image_from_graph.py` + `.pre-commit-config.yaml` all name the old path literally. All four must update atomically.
   - **Templates reference old path**: `docs/stories/_template.md` + `docs/plan/_template.md` + `docs/stories/FG-086-docs-structure.md` (this file!) must point to `docs/specs/CAPABILITIES.md`.
7. **Out of scope** —
   - Renaming any FG-NNN to match the new scheme (they already match).
   - Introducing SPEC-NN numbering (the scope-1 option from decision iteration 1 — rejected; specs stay topic-named).
   - Rewriting historical FG-*-plan.md / FG-*.md to use new paths.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_086_docs-structure.sh`.
9. **Capabilities delivered or extended** —
   - NEW `docs.three-folder-structure` — `docs/` top-level is exactly `{specs, plan, stories}/`; each subdir has a known allowed file set.
   - NEW `docs.no-stale-refs-gate` — `scripts/verify-docs-structure.sh` ensures no active file references the pre-FG-086 paths (CAPABILITIES.md et al at docs/ root, or tier-layering-model.md under docs/plan/).

## Gherkin acceptance

```
Scenario: Layout after FG-086
  Given FG-086 has shipped
  Then docs/ contains only three subdirectories: specs/, plan/, stories/
   And docs/specs/ contains CAPABILITIES.md, LAYERING.md, baseline-contract.md,
       differentiators.md, tier-layering-model.md, image-dependency-graph.md,
       image-dependency-graph.svg
   And docs/plan/ contains only FG-NNN-*-plan.md, IDEAS.md, _template.md
   And docs/stories/ contains only FG-NNN-*.md, INDEX.md, _template.md, _9-questions.md

Scenario: No active file references the old paths
  Given FG-086 has shipped
  When I grep active (non-historical) files for pre-FG-086 doc paths
  Then every active reference resolves to its new docs/specs/ location
   And historical docs/plan/FG-*-plan.md + docs/stories/FG-*.md are explicitly excluded

Scenario: Structural gate blocks future drift
  Given FG-086 has shipped
  When someone creates docs/notes.md at docs/ top level
  Then make test-fast fails with a verify-docs-structure error
```

## References

- Spec: `docs/specs/docs-structure.md`
- Plan: `docs/plan/FG-086-docs-structure-plan.md`
- Red test: `tests/acceptance/test_FG_086_docs-structure.sh`
- Capabilities: see `docs/specs/CAPABILITIES.md`
