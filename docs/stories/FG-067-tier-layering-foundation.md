---
id: FG-067
slug: tier-layering-foundation
status: in-progress
owner: bboortz
created: 2026-11-20
---

# FG-067 — Tier-layering foundation (policy + tooling, zero image moves)

Lock the 7-tier Forge model from `docs/plan/tier-layering-model.md` as the official convention. Document the tier definitions in `memory/docker-standard.md`, register the two foundational CAPs, and add a negative-guard lint rule that prevents the retired `source/` tier from re-surfacing. No image moves. No consumer contracts broken. Zero blast radius beyond forge's own docs + lint.

## 9 canonical answers

1. **Who** — Forge maintainer about to start the 4 sequential tier-move FGs (FG-068 → FG-071). Needs the tier definitions codified in `memory/` (which is loaded in every Claude session) + a lint guard that makes "re-add `images/source/`" impossible.

2. **When** — Fires exactly once as the foundation PR before FG-068. Re-fires only if a future author bypasses the lint and tries to create `images/source/*`.

3. **What success looks like**:
   - `memory/docker-standard.md` grows a new § "7-tier layering model" with the crisp definitions from `docs/plan/tier-layering-model.md` §3.
   - `docs/CAPABILITIES.md` registers `arch.tier-prefix-convention` + `arch.layer-overlap-resolution` (both NEW).
   - `scripts/verify-dockerfile-conformance.py` gains **Rule 11** — negative guard against the retired `source/` tier.
   - `tests/acceptance/test_FG_067_tier-layering-foundation.sh` asserts: memory § present; CAPs registered; Rule 11 fires on a synthetic `images/source/foo/Dockerfile`; current fleet still passes.
   - `make test-fast` + `make check` green on dev.

4. **Urgency** — Prerequisite for FG-068 + FG-069 + FG-070 + FG-071. Foundation.

5. **Happy path**:
   1. Branch `feat/FG-067-tier-layering-foundation` from `dev` (which now has `docs/plan/tier-layering-model.md` committed via the docs PR).
   2. Red acceptance test — assertions listed above.
   3. Implementation: 4 files touched (memory, CAPABILITIES, conformance.py, test).
   4. Local `make check`, local run of the acceptance test, local run of `verify-dockerfile-conformance.py` against the current fleet.
   5. PR → CI → auto-merge → next 03:00 UTC cron picks up nothing new (no image moved).

6. **Edge cases / failure modes**:
   - **Rule 11 false positives**: if someone legitimately uses the token "source" in a comment or a variable name inside a Dockerfile, Rule 11 must not fire. Scope the rule to **directory existence only** (`images/source/` tree walk), not line-level string matching.
   - **CAP registration + traceability**: both new CAPs must have `Covered by:` pointers immediately; the acceptance test IS the pointer. Verify `make verify-traceability` green.
   - **Memory file size cap**: `memory/*.md` files are capped at 150 lines per `memory/code-quality.md`. New § "7-tier layering model" summary must be brief; link to `docs/plan/tier-layering-model.md` for the full table.

7. **Out of scope**:
   - Any image directory move — those land in FG-068+.
   - `_UPSTREAM_SOURCES` inventory — lands in FG-068 (L0.1 tooling).
   - Rule 12 (base/ constraint) — lands in FG-069 when `base/` dirs exist.
   - Rule enforcement in `discover-images.sh` for new tier modes — current modes already cover what FG-067 needs; enriched modes land per-FG as needed.
   - `scripts/image_from_graph.py` L0.1 subgraph emission — lands in FG-068.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `arch.tier-prefix-convention` — the invariant that tier membership is encoded in the directory prefix (`mirror/`, `pre-builder/`, `builder/`, `base/`) OR the flat L4 position. Every image under `images/` belongs to exactly one tier; the path tells you which.
   - NEW `arch.layer-overlap-resolution` — the semantic-test ordering from §4 of the plan doc: L0 vs L0.1 (transport), L0.5 vs L1 (Rule 10), L2 vs rest ("runs at runtime?"), L3 vs L4 (forge-internal consumer?), L4 absorbs from-source + externally-sourced.

## Gherkin acceptance

```
Scenario: memory/docker-standard.md documents the 7-tier model
  Given current HEAD
  Then memory/docker-standard.md contains a § "7-tier layering model"
  And that § names at least L0, L0.1, L0.5, L1, L2, L3, L4
  And it links to docs/plan/tier-layering-model.md for the full table

Scenario: docs/CAPABILITIES.md registers the foundation CAPs
  Given current HEAD
  Then docs/CAPABILITIES.md contains "### arch.tier-prefix-convention"
  And it contains "### arch.layer-overlap-resolution"
  And both CAPs carry a "Covered by:" pointer to this story's acceptance test

Scenario: Rule 11 (negative guard against retired source/ tier)
  Given scripts/verify-dockerfile-conformance.py
  Then it contains a Rule 11 check that fails if any images/source/ tree exists
  When a synthetic images/source/foo/Dockerfile is created in a tmp images root
  Then the rule's logic — simulated with a small Python shim — flags images/source/
  And the real-fleet run of verify-dockerfile-conformance.py (no images/source/ today) still exits 0

Scenario: make verify-traceability green with the new CAPs
  Given current HEAD
  When `make verify-traceability` runs
  Then it exits 0
  And both new CAPs appear in its "tracked CAP" output

Scenario: no image directory was moved
  Given the diff between dev and this PR
  Then no file under images/<tier>/ is created or renamed
  And no scratch-base-trixie, python-scratch-trixie, or forge-builder-* rename occurs
  And the dep graph contents of docs/image-dependency-graph.{md,svg} are byte-identical before and after
```

## References

- Plan: `docs/plan/FG-067-tier-layering-foundation-plan.md` (follow-up)
- Red test: `tests/acceptance/test_FG_067_tier-layering-foundation.sh` (follow-up)
- Tier model: `docs/plan/tier-layering-model.md` § 3 + § 4 + § 6 (all O1-O9 resolved)
- Downstream dependencies: FG-068 (L0.1 tooling), FG-069 (base/ move), FG-070 (pre-builder/ move), FG-071 (builder/ move + rename).
