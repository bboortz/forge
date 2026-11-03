---
id: FG-NNN
slug: <kebab-case-slug>
status: draft           # draft → ready → in-progress → shipped
owner: <github-handle>
created: YYYY-MM-DD
---

# FG-NNN — <one-line title>

<One paragraph: who this is for, what changes for them, why now.>

## 9 canonical answers

See `_9-questions.md` for the question set.

1. **Who** —
2. **When** —
3. **What success looks like** —
4. **Urgency** —
5. **Happy path** —
6. **Edge cases / failure modes** —
7. **Out of scope** —
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended** — list CAP ids; mark `NEW` or `EXT`:

   - NEW `<cap.id>` — one-line description
   - EXT `<cap.id>` — what this story adds to the existing CAP

## Gherkin acceptance

```
Scenario: <name>
  Given <precondition>
  When <action>
  Then <observable>
   And <observable>
```

(Add one Scenario block per acceptance criterion. Every Scenario must have a pointer in the plan doc's Shipping evidence table.)

## References

- Plan: `docs/plan/FG-NNN-<slug>-plan.md`
- Red test: `tests/acceptance/test_FG_NNN_<slug>.sh`
- Capabilities: see `docs/CAPABILITIES.md`
