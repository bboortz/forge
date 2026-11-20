# FG-067 — Plan: Tier-layering foundation

**Story**: [`docs/stories/FG-067-tier-layering-foundation.md`](../stories/FG-067-tier-layering-foundation.md)
**Status**: in-progress
**Branch**: `feat/FG-067-tier-layering-foundation`

## Design delta

Codify the 7-tier model in the authoritative places. Three concrete changes:

1. **`memory/docker-standard.md`** grows a new § "7-tier layering model" that summarizes the tier prefixes + their one-line definitions, with a pointer to `docs/plan/tier-layering-model.md` for the full semantic-test table. Stays under the 150-line cap by linking out, not inlining.
2. **`docs/CAPABILITIES.md`** registers two foundational CAPs — `arch.tier-prefix-convention` + `arch.layer-overlap-resolution`. Both get `Covered by:` pointers to this FG's acceptance test.
3. **`scripts/verify-dockerfile-conformance.py`** gains **Rule 11** — a negative guard: if any `images/source/` tree exists, lint fails. This prevents the retired tier concept from re-surfacing in a future PR by accident. Rule 11 is directory-scoped (not line-scoped), so any legitimate "source" string in comments / variable names is untouched.

No image moves. No consumer breakage.

## Alternatives rejected

- **Inlining the full tier table in `memory/docker-standard.md`** — would exceed the 150-line memory cap and drift from the plan doc. Rejected: link out instead.
- **Rule 11 as a line-level grep** — would false-positive on legitimate "source" tokens. Rejected: directory-walk only.
- **Add Rule 12 (base/ constraint) now** — Rule 12 is "every `base/` image must FROM scratch + have ≥1 forge-internal consumer." But no `base/` dirs exist yet; Rule 12 fires vacuously or false-positives. Rejected: defer to FG-069 when the dirs land.
- **Add `_UPSTREAM_SOURCES` inventory now** — belongs in FG-068 (L0.1 tooling). FG-067 is pure-foundation; keep scope tight.

## Breaking changes

**None.** Docs + lint rule additions. No image contract touched.

## Merge plan

Must pass to merge to `dev`:
- `hadolint`, `shellcheck`, `yamllint` green
- `make verify-traceability` green (both new CAPs documented + covered)
- `python3 scripts/verify-dockerfile-conformance.py` green on the current fleet (Rule 11 does NOT fire because `images/source/` doesn't exist)
- `make test-acceptance` green including `test_FG_067_tier-layering-foundation.sh`

No gates waived.

## Rollout plan

Default path: PR → `dev` → next release promotion. No publish-time impact (no image changed). The daily cron is unaffected.

## Shipping evidence

Filled at pre-ship audit (step 6a).

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: memory docs the 7-tier model | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` §1 | ✅ |
| Scenario: CAPABILITIES registers the two CAPs | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` §2 | ✅ |
| Scenario: Rule 11 negative guard | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` §3 | ✅ |
| Scenario: traceability green | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` §4 | ✅ |
| Scenario: no image moves | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` §5 | ✅ |
| CAP `arch.tier-prefix-convention` | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` + `docs/CAPABILITIES.md#archtier-prefix-convention` | ✅ |
| CAP `arch.layer-overlap-resolution` | `tests/acceptance/test_FG_067_tier-layering-foundation.sh` + `docs/CAPABILITIES.md#archlayer-overlap-resolution` | ✅ |
