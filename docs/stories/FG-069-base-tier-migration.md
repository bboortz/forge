---
id: FG-069
slug: base-tier-migration
status: in-progress
owner: bboortz
created: 2026-11-20
---

# FG-069 — base/ tier migration (L3 formalized)

Move the two existing scratch-runtime foundation images into `images/base/`, dropping the now-redundant leaf-name tokens that the tier prefix encodes: `scratch-base-trixie` → `base/scratch-trixie` and `python-scratch-trixie` → `base/python-trixie`. First FG in the series that actually relocates images. Updates 9 scratch-runtime Dockerfiles' `ARG SCRATCH_BASE_REF` default + 12 `image.yaml depends_on:` entries + 12 EXPECTATIONS cross-refs + 4 scripts. Adds Rule 12 (base/ images must FROM scratch + have ≥1 forge-internal consumer).

Paired Beaconry PR coordinates the 3 Dockerfiles that `FROM ghcr.io/bboortz/python-scratch-trixie:latest` (per tier-plan §O5).

## 9 canonical answers

1. **Who** — Forge maintainer + external Beaconry consumer. Internal consumers (9 scratch runtimes) are forge-owned and update in the same PR. External consumer (Beaconry) ships a coordinated PR.

2. **When** — Fires at merge time: (a) forge PR flips every internal reference; (b) forge release promotes `main`; (c) daily cron publishes `base/scratch-trixie:latest` + `base/python-trixie:3.14` under the new paths; (d) Beaconry PR merges + re-builds against the new path.

3. **What success looks like**:
   - `images/base/scratch-trixie/` + `images/base/python-trixie/` exist with full contract set (Dockerfile, image.yaml, PROMISES.yaml, EXPECTATIONS.yaml, scan-baseline.json, sid-pins/, tests/).
   - Old flat paths gone: no `images/scratch-base-trixie/`, no `images/python-scratch-trixie/`.
   - 9 scratch-runtime Dockerfiles' `ARG SCRATCH_BASE_REF` points at `ghcr.io/bboortz/base/scratch-trixie:latest`.
   - 12 `image.yaml depends_on:` entries updated (9 scratch-base consumers + 3 beaconry python consumers).
   - 12 `EXPECTATIONS.yaml` cross-refs updated (image: field + preflight paths).
   - 2 PROMISES.yaml `image:` fields updated to leaf names (`scratch-trixie`, `python-trixie`) per the mirror/syft convention.
   - `scripts/verify-dockerfile-conformance.py` `_BASELINE` set updated + **Rule 12** added + lint green.
   - `scripts/verify-contracts.py` preflight-path check broadened to accept `images/*/*/tests/` (base/ + mirror/ nesting).
   - `scripts/image_from_graph.py` `_BASELINE` list updated + dep graph regenerated: both base/ images render under L3 (`:::baseline` style).
   - `scripts/build-image.sh` SCRATCH_BASE_REF resolution paths updated.
   - `scripts/smart-check.sh` FULL_RE trigger updated.
   - `docs/CAPABILITIES.md` registers `build.base-tier` + `arch.base-tier-images` (both NEW).
   - `memory/docker-standard.md` notes Rule 12 + new paths.
   - `docs/image-dependency-graph.{md,svg}` regenerated.
   - `tests/acceptance/test_FG_069_base-tier-migration.sh` asserts: new paths present; old paths gone; consumer ARG defaults updated; `depends_on` updated; Rule 12 fires on a synthetic zero-consumer base image + non-scratch final FROM; discover-images / dep-graph classification correct; traceability green.
   - `make test-fast` + `make check` green on dev.
   - **Beaconry PR**: 3 Dockerfiles' FROM `python-scratch-trixie:latest` → `base/python-trixie:latest`. Opens simultaneously with forge PR; merges after forge publishes.

4. **Urgency** — Prerequisite for FG-070 + FG-071 renames. Also the first migration FG to produce a user-visible GHCR path change (Beaconry affected).

5. **Happy path**:
   1. Branch `feat/FG-069-base-tier-migration` from dev (post-FG-068).
   2. `git mv` the 2 directories.
   3. Red test → sed renames across consumers → scripts update → regen dep graph → Rule 12 added.
   4. Local `make test-fast` green; `make verify-contracts` green.
   5. Open forge PR + beaconry PR simultaneously. Beaconry PR gated on forge publish.
   6. CI full suite → auto-merge forge PR → forge release promotes main → daily cron publishes new paths → merge beaconry PR.

6. **Edge cases / failure modes**:
   - **Beaconry build race**: between forge-publish and beaconry-merge, beaconry's next rebuild pulls STALE `python-scratch-trixie:latest` (last pre-FG-069 digest). Acceptable brief window; beaconry PR closes it within hours.
   - **PROMISES `image:` field**: must be the LEAF name (`scratch-trixie`), not the canonical path (`base/scratch-trixie`), because `verify-contracts.py` compares against the directory leaf. Mirror/syft precedent (`image: syft`).
   - **Preflight path check in verify-contracts.py**: the old check required `images/<leaf>/tests/<script>` (3 path parts, tests at idx 1). Nested `images/base/<leaf>/tests/<script>` is 4 parts, tests at idx 2 — relaxed to accept both forms. Same pattern mirror/<name>/tests/ needed when FG-066 shipped.
   - **ARG name stays `SCRATCH_BASE_REF`**: semantic ("the scratch base reference"); only the default value changes. Avoids a cascade rename across 9 Dockerfiles + `_KNOWN_REF_ARGS`.
   - **Tag preservation**: `base/scratch-trixie:latest` keeps the `tag: "0.2"` published family (:0.2 + :latest); `base/python-trixie:3.14` preserves the Python-version tagging. No tag-format change.
   - **Rule 12 false-positive on healthy-scratch-trixie**: healthy is `FROM scratch` directly (no overlay) but is at a flat L4 path (not `base/`). Rule 12 scopes to `base/*` only — healthy unaffected.
   - **No new CI tier**: `publish-base` already exists via `discover-images.sh base` mode. Post-rename, `base/scratch-trixie` (no deps) goes to `publish-base`; `base/python-trixie` (depends on base/scratch-trixie) goes to `publish-derivatives` — same as pre-rename flow for python-scratch-trixie.

7. **Out of scope**:
   - Moving pre-builders — that's FG-070.
   - Moving builders + renaming `forge-builder-*` prefix — that's FG-071.
   - Changing L4 runtime paths (flat positions preserved).
   - Beaconry's own CI or downstream deployment changes beyond the 3 Dockerfile `FROM` flips.
   - Deleting the legacy GHCR repos at `ghcr.io/bboortz/scratch-base-trixie` + `ghcr.io/bboortz/python-scratch-trixie` — they just stop being updated. If an explicit sunset is wanted, that's a separate chore.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `build.base-tier` — formalizes L3 as a first-class CI publish tier with Rule 12 enforcement (final-stage FROM scratch + ≥1 forge-internal consumer).
   - NEW `arch.base-tier-images` — invariant that L3 images live under `images/base/`, have leaf-name `image:` fields in PROMISES, and are reachable at `base/<leaf>` canonical paths via tooling.
   - EXT `build.two-stage-scratch` — python-scratch-trixie's scratch-overlay shape preserved under the new path.
   - EXT `test.image-smoke-suite` — base/<name>/tests/ walk already supported post-FG-066's two-level walker.

## Gherkin acceptance

```
Scenario: new paths exist + old paths gone
  Given current HEAD
  Then images/base/scratch-trixie/ + images/base/python-trixie/ exist
  And images/scratch-base-trixie/ + images/python-scratch-trixie/ do NOT exist

Scenario: PROMISES image: fields use leaf names (mirror/syft convention)
  Given images/base/scratch-trixie/PROMISES.yaml
  Then it contains `image: scratch-trixie` (NOT `base/scratch-trixie`)
  Given images/base/python-trixie/PROMISES.yaml
  Then it contains `image: python-trixie` (NOT `base/python-trixie`)

Scenario: 9 scratch-runtime Dockerfiles updated to new ARG default
  Given every scratch-runtime Dockerfile that declared SCRATCH_BASE_REF
  Then its default value is ghcr.io/bboortz/base/scratch-trixie:latest
  And no Dockerfile references ghcr.io/bboortz/scratch-base-trixie

Scenario: 12 image.yaml depends_on entries updated
  Given every image.yaml depends_on list in the fleet
  Then no entry is "scratch-base-trixie" or "python-scratch-trixie"
  And the 9 scratch-runtime consumers list "base/scratch-trixie"
  And the 3 beaconry consumers list "base/python-trixie"

Scenario: EXPECTATIONS cross-refs updated
  Given every EXPECTATIONS.yaml referencing the renamed bases
  Then image: dep refs use the new names (base/scratch-trixie, base/python-trixie)
  And preflight: test paths point under images/base/<leaf>/tests/

Scenario: Rule 12 — base/ images FROM scratch
  Given scripts/verify-dockerfile-conformance.py Rule 12
  And a synthetic images/base/bad/Dockerfile with `FROM python:3.14-slim-trixie` + no consumer
  Then the rule flags the non-scratch FROM
  And flags the zero-consumer condition
  Given the real fleet (base/scratch-trixie + base/python-trixie)
  Then both pass Rule 12 (FROM scratch + have ≥1 consumer)

Scenario: discover-images places base/ entries correctly
  Given scripts/discover-images.sh
  When `base` mode runs
  Then it contains "base/scratch-trixie" (no depends_on)
  When `derivatives` mode runs
  Then it contains "base/python-trixie" (depends_on: base/scratch-trixie)

Scenario: dep graph renders both base/ images under L3
  Given regenerated docs/image-dependency-graph.md
  Then L3_baseline subgraph contains BOTH base/scratch-trixie AND base/python-trixie
  And both nodes carry :::baseline styling (not :::slim)

Scenario: verify-* all green on current HEAD
  Given current HEAD
  When make test-fast runs
  Then every gate exits 0

Scenario: traceability green with new CAPs
  Given docs/CAPABILITIES.md
  Then it contains "### build.base-tier"
  And it contains "### arch.base-tier-images"
  And both have "Covered by:" pointers

Scenario: memory + docs reference the new paths + Rule 12
  Given memory/docker-standard.md
  Then it contains "Rule 12"
  And it contains "base/scratch-trixie" + "base/python-trixie"
```

## References

- Plan: `docs/plan/FG-069-base-tier-migration-plan.md`
- Red test: `tests/acceptance/test_FG_069_base-tier-migration.sh`
- Tier model: `docs/plan/tier-layering-model.md` §O2+O3 (rename decisions) + §3 L3 + §7 FG-069
- Coordinated: Beaconry PR (3 Dockerfiles `FROM python-scratch-trixie:latest` → `FROM base/python-trixie:latest`) — opened in `bboortz/beaconry` simultaneously; merged post forge-publish.
