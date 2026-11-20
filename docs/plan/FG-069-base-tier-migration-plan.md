# FG-069 — Plan: base/ tier migration

**Story**: [`docs/stories/FG-069-base-tier-migration.md`](../stories/FG-069-base-tier-migration.md)
**Status**: in-progress
**Branch**: `feat/FG-069-base-tier-migration`

## Design delta

First FG in the migration run that actually relocates images. Three scopes of change:

1. **Directory + GHCR path renames** (`git mv` × 2):
   - `images/scratch-base-trixie` → `images/base/scratch-trixie` (drops `-base-` token)
   - `images/python-scratch-trixie` → `images/base/python-trixie` (drops `-scratch-` token)

2. **Reference updates** across the repo:
   - 9 Dockerfile `ARG SCRATCH_BASE_REF` defaults → `ghcr.io/bboortz/base/scratch-trixie:latest`
   - 12 `image.yaml depends_on:` entries (9 scratch-base refs + 3 python refs)
   - 12 `EXPECTATIONS.yaml` dep-image refs + preflight test paths
   - 2 `PROMISES.yaml image:` fields (use leaf names per mirror/syft convention)
   - 4 scripts (`verify-dockerfile-conformance.py`, `image_from_graph.py`, `build-image.sh`, `smart-check.sh`) + `.github/workflows/build.yml` comment

3. **Tooling additions**:
   - **Rule 12** in `verify-dockerfile-conformance.py` — base/ images must FROM scratch (final stage) AND have ≥1 forge-internal consumer in `depends_on`.
   - `verify-contracts.py` preflight path check accepts `images/*/*/tests/` nesting (parallel with mirror/).

Paired **Beaconry PR** flips 3 Dockerfiles' `FROM python-scratch-trixie:latest` → `FROM base/python-trixie:latest` in the `bboortz/beaconry` repo. Opens simultaneously; merges after forge publishes the new path.

## Alternatives rejected

- **Keep full leaf names** (`base/scratch-base-trixie`, `base/python-scratch-trixie`) — tier-plan §O2+O3 chose to drop the redundant tokens because the tier prefix encodes the "scratch-assembled runtime foundation" semantic. Visually cleaner.
- **Rename ARG `SCRATCH_BASE_REF` → `BASE_SCRATCH_REF`** — would cascade across 9 Dockerfiles + `_KNOWN_REF_ARGS`. ARG name is semantic, not path-tied. Rejected.
- **Dual-publish old + new paths during transition** — rejected per tier-plan §O6 (rope to hang the next migration).
- **Defer Rule 12 to a follow-up** — Rule 12's purpose is to prevent future `base/` additions from violating the L3 semantic test. Lands with the migration, otherwise FG-069 is the LAST moment the invariant isn't enforced.
- **Use canonical path `base/scratch-trixie` as `image:` field** — `verify-contracts.py` compares against the directory leaf; mirror/syft set the precedent (`image: syft`). Rejected the canonical form to stay consistent.

## Breaking changes

**Yes — user-visible GHCR path change**:
- Consumers pulling `ghcr.io/bboortz/scratch-base-trixie:0.2` or `:latest` must migrate to `ghcr.io/bboortz/base/scratch-trixie:...`. Forge has no known external consumer here (it's a builder-stage overlay, not a runtime pull target).
- Consumers pulling `ghcr.io/bboortz/python-scratch-trixie:3.14` must migrate to `ghcr.io/bboortz/base/python-trixie:3.14`. Forge's known external consumer is Beaconry (3 Dockerfiles) — handled by the coordinated PR.

Legacy GHCR repos are NOT deleted; they just stop being updated. External pulls at the old path return the last pre-FG-069 digest indefinitely.

## Merge plan

Must pass to merge to `dev`:
- Lint + verify-* green (including the new `verify-source-inventory` from FG-068 + Rule 12 from FG-069)
- `make verify-contracts` green (preflight-path check now accepts `images/*/*/tests/`)
- `make verify-traceability` green (new CAPs documented + covered)
- `make verify-dep-graph-fresh` green (regenerated graph committed)
- `make test-acceptance` green including `test_FG_069_base-tier-migration.sh`

No gates waived.

## Rollout plan

1. Forge PR merges to `dev`.
2. Forge release promotes `main` → next publish → `ghcr.io/bboortz/base/{scratch,python}-trixie:*` live.
3. Beaconry PR merges in `bboortz/beaconry` → next beaconry rebuild pulls new path.

The Beaconry PR is opened simultaneously with forge-PR-open. It sits at **requested-changes-pending-forge-publish** until forge main promotes.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| New paths exist + old gone | `test_FG_069_base-tier-migration.sh` §1 | ✅ |
| PROMISES image: leaf names | §2 | ✅ |
| 9 Dockerfile ARG defaults updated | §3 | ✅ |
| 12 image.yaml depends_on updated | §4 | ✅ |
| 12 EXPECTATIONS cross-refs updated | §5 | ✅ |
| Rule 12 negative + positive | §6 | ✅ |
| discover-images classification | §7 | ✅ |
| Dep graph L3 renders both | §8 | ✅ |
| make test-fast green | §9 | ✅ |
| Traceability + new CAPs | §10 | ✅ |
| Memory + docs updated | §11 | ✅ |
| CAP `build.base-tier` | test + CAPABILITIES.md | ✅ |
| CAP `arch.base-tier-images` | test + CAPABILITIES.md | ✅ |
