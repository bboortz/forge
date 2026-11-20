# FG-071 — Plan: builder/ tier migration

**Story**: [`docs/stories/FG-071-builder-tier-migration.md`](../stories/FG-071-builder-tier-migration.md)
**Status**: ready → shipped
**Branch**: `feat/FG-071-builder-tier-migration`
**Parent**: `docs/plan/tier-layering-model.md` §7 FG-071 subsection

## Design delta

The 4 L2 forge-builders (`forge-builder-{python,go,node,zig}-trixie`) relocate from flat `images/<name>/` to nested `images/builder/<lang>-trixie/`. GHCR repos follow — `ghcr.io/bboortz/builder/<lang>-trixie:<tag>`. Downstream consumers' ARG names shed the `FORGE_BUILDER_` prefix in favour of `BUILDER_<LANG>_REF` (cleaner — the tier is now encoded by the repo path, not the ARG), and ARG defaults flip to the new GHCR paths. This closes the 7-tier model (FG-067) — after FG-071, no bare `forge-builder-*` or tier-encoded-in-leaf remains.

The rename pattern mirrors FG-069 (base/) + FG-070 (pre-builder/):
- Dir: `images/forge-builder-<lang>-trixie/` → `images/builder/<lang>-trixie/`
- Repo: `ghcr.io/bboortz/forge-builder-<lang>-trixie:<tag>` → `ghcr.io/bboortz/builder/<lang>-trixie:<tag>`
- ARG: `FORGE_BUILDER_REF` / `FORGE_BUILDER_<LANG>_REF` → `BUILDER_<LANG>_REF`
- image.yaml: adds explicit `repo: builder/<lang>-trixie` (required for nested paths — matches mirror/syft precedent)
- PROMISES / EXPECTATIONS `image:` field: keeps leaf name (`python-trixie`) consistent with FG-069 convention.

## Alternatives rejected

- **Keep the `forge-builder-` prefix in `images/builder/`** (e.g. `images/builder/forge-builder-python-trixie/`) — redundant: the `builder/` tier prefix already encodes the semantic. The `forge-builder-` prefix was from the flat era when no tier directory existed.
- **Keep ARG names `FORGE_BUILDER_*_REF`** — bikeshed; but after dropping `forge-` from the dir, the ARG name reads oddly without the matching rename. One-shot alignment is cheaper than a split naming later.
- **Dual-publish old + new GHCR repos during a grace window** — rejected per decision O6 in the tier-plan. We hard-flip; if an external consumer appears later they can discover the new path from the `repo:` field or the public docs.

## Breaking changes

**None public**. Builders only appear in the builder-stage of multi-stage builds inside the Forge repo. External consumers (Beaconry, homelab-bots, etc.) never reference `ghcr.io/bboortz/forge-builder-*` because they aren't runtimes. The old GHCR repos will stop receiving updates; existing tags remain fetchable for anyone who happens to have pinned a digest.

## Merge plan

Full `memory/workflow.md § Blocking gates` matrix. Image-touching so: `make build && make scan && make verify` against local digests after cold-cache rebuild. No gates waived.

Pre-push: `make check-strict` (clean local images + full check). PR CI runs acceptance + traceability + conformance + drift + source-inventory + dep-graph freshness.

## Rollout plan

Default path:
1. PR → dev (auto-merge on green CI)
2. Manual `release.yml` dispatch — fast-forward main from dev
3. Manual `build.yml` dispatch on main — publishes 4 `builder/*` tags
4. Verify 4 tags live on GHCR with cosign-verifiable identity bound to `.github/workflows/build.yml`.

## Shipping evidence

Filled at pre-ship audit. All rows ✅ before merge.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: 4 builders live under images/builder/ | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§1` | ✅ |
| Scenario: image.yaml declares explicit nested repo | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§2` | ✅ |
| Scenario: consumers use the new ARG names | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§3` | ✅ |
| Scenario: discover-images lists 4 builders under builder/ | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§4` | ✅ |
| Scenario: dep graph L2 subgraph renders 4 builders with normalized ids | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§6` | ✅ |
| Scenario: verify-no-upstream-drift unchanged | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§5` | ✅ |
| CAP `build.builder-migrated` | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§1-§4` + `docs/CAPABILITIES.md#build.builder-migrated` | ✅ |
| CAP `arch.builder-tier-images` | `tests/acceptance/test_FG_071_builder-tier-migration.sh:§1-§7` + `docs/CAPABILITIES.md#arch.builder-tier-images` | ✅ |
