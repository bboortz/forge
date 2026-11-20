# FG-068 — Plan: L0.1 upstream-source tooling

**Story**: [`docs/stories/FG-068-l0-1-source-tooling.md`](../stories/FG-068-l0-1-source-tooling.md)
**Status**: in-progress
**Branch**: `feat/FG-068-l0-1-source-tooling`

## Design delta

Three concrete deliverables + supporting wiring:

1. **`scripts/_upstream_sources.py`** — single-source-of-truth dict mapping canonical source URLs to their consumer image-dir names. 10 entries covering today's actual references. Also exports `canonical_url()` helper.
2. **`scripts/verify-source-inventory.py`** — two-way sync checker. Forward: every actual `RUN git clone <URL>` / `image.yaml source.git: <URL>` reference must be in the inventory + the referencing image declared as a consumer. Reverse: every inventory entry must have ≥1 declared consumer that actually references the URL.
3. **`scripts/image_from_graph.py`** gains an **L0.1 subgraph** + dashed edges from each source to its declared consumers. Uses `_UPSTREAM_SOURCES` directly — stays in sync with the verifier by construction.

Wired into `make test-fast` via a new `verify-source-inventory` target. Documented in `memory/docker-standard.md` + `docs/CAPABILITIES.md`.

No image moves. `images/` tree byte-identical.

## Alternatives rejected

- **Move beaconry + healthy into `images/source/`** (original FG-068 scope) — retired when L4.5 was dropped per tier-plan §O8. L4 absorbs from-source + externally-sourced runtimes.
- **Inline inventory in each image.yaml** — would require walking every image.yaml at verify time; also makes "where does `uptime-kuma-slim-trixie` get its source?" into N file reads instead of one. Rejected: centralized inventory is grep-able.
- **Use PyYAML in verify-source-inventory.py** — not in the stdlib; conformance.py avoids it; parsing `source.git:` is simple enough to do without. Rejected: dependency bloat.
- **Scan for `git clone` keyword, not generic URL regex** — misses multi-line `\`-continued invocations. Rejected: whole-file URL scan with `_SKIP` filter is more robust.
- **Fail-soft on missing inventory module** — dep-graph emitter gracefully falls back to empty inventory. The acceptance test catches the drift separately.

## Breaking changes

**None.** New module + new verifier + new Makefile target. Existing Dockerfiles untouched.

## Merge plan

Must pass to merge to `dev`:
- Lint (`hadolint`, `shellcheck`, `yamllint`) green
- `make verify-traceability` green (both new CAPs documented + covered)
- `python3 scripts/verify-source-inventory.py` exits 0 on the current fleet
- `python3 scripts/image_from_graph.py --emit=mermaid` output contains the L0.1 subgraph
- `make verify-dep-graph-fresh` green (artifacts regenerated + committed)
- `make test-acceptance` green including `test_FG_068_l0-1-source-tooling.sh`

No gates waived.

## Rollout plan

Default path: PR → `dev` → next release promotion. No publish-time impact.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: inventory module shape | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §1 | ✅ |
| Scenario: verifier runs clean on HEAD | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §2 | ✅ |
| Scenario: verifier catches missing-entry drift | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §3 | ✅ |
| Scenario: verifier catches undeclared-consumer drift | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §4 | ✅ |
| Scenario: dep graph L0.1 subgraph + edges | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §5 | ✅ |
| Scenario: Makefile wires verify-source-inventory | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §6 | ✅ |
| Scenario: CAPs + memory documented | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §7 | ✅ |
| Scenario: no image moves | `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` §8 | ✅ |
| CAP `build.l0-1-source-inventory` | acceptance test + `docs/CAPABILITIES.md#buildl0-1-source-inventory` | ✅ |
| CAP `arch.l4-absorbs-from-source` | acceptance test + `docs/CAPABILITIES.md#archl4-absorbs-from-source` | ✅ |
