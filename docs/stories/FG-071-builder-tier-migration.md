---
id: FG-071
slug: builder-tier-migration
status: ready
owner: bboortz
created: 2026-11-20
---

# FG-071 — builder/ tier migration (last tier move; largest blast)

The L2 tier physically relocates from flat `images/forge-builder-{python,go,node,zig}-trixie/` to nested `images/builder/{python,go,node,zig}-trixie/`, with GHCR repos following (`ghcr.io/bboortz/builder/<lang>-trixie:<tag>`). Consumer Dockerfiles across every scratch/slim runtime that currently FROMs a `forge-builder-*` upstream flip their `ARG FORGE_BUILDER_*_REF` → `ARG BUILDER_*_REF` and their defaults from `.../forge-builder-<lang>-trixie:...` → `.../builder/<lang>-trixie:...`. Shape identical to FG-069 (base/) + FG-070 (pre-builder/) — this is the fourth and final tier move that closes the 7-tier layering model (FG-067).

## 9 canonical answers

1. **Who** — Forge maintainers; downstream image owners whose Dockerfiles reference `${FORGE_BUILDER_*_REF}`. External consumers (Beaconry, homelab bots) see no visible effect — they don't FROM builders; builders only appear in builder-stage of multi-stage builds.
2. **When** — Fires when a new runtime wants to build from source against a forge-controlled toolchain, OR when an existing consumer bumps language version / toolchain.
3. **What success looks like** —
   - 4 image dirs live at `images/builder/<lang>-trixie/`; the 4 flat paths are gone.
   - Each has explicit `repo: builder/<lang>-trixie` in `image.yaml`.
   - 11 consumer Dockerfiles (8 python + 7 go + 3 node — some overlap: alertmanager, prometheus, postgres-slim, ipmi-exporter-scratch) use `ARG BUILDER_<LANG>_REF=ghcr.io/bboortz/builder/<lang>-trixie:latest` and FROM `${BUILDER_<LANG>_REF}`.
   - No `FORGE_BUILDER_*_REF` / `forge-builder-` literals remain in Dockerfiles.
   - discover-images.sh, conformance lint, dep graph, build-image.sh, Makefile all updated.
   - `_EXPECTED=6` in verify-no-upstream-drift unchanged (builders don't FROM Docker Hub directly post-FG-065).
   - CI publishes 4 `builder/*` tags to GHCR on main-cron.
4. **Urgency** — Quality-of-life. No CVE pressure. Blocks closing FG-067 (7-tier model complete).
5. **Happy path** —
   1. `git mv images/forge-builder-<lang>-trixie images/builder/<lang>-trixie` × 4
   2. Add `repo: builder/<lang>-trixie` to each image.yaml
   3. Rename `FORGE_BUILDER_REF` → `BUILDER_PYTHON_REF` + `FORGE_BUILDER_<LANG>_REF` → `BUILDER_<LANG>_REF` across 11 Dockerfiles; update ARG defaults to `.../builder/<lang>-trixie:...`
   4. Update tool allowlists: discover-images.sh `_BUILDERS`, verify-dockerfile-conformance.py `_BUILDERS` + `_KNOWN_REF_ARGS`, image_from_graph.py `_BUILDERS` + `_KNOWN_REF_ARGS`, build-image.sh needs_forge_builder case (`builder/*`)
   5. Update PROMISES + EXPECTATIONS `image:` fields; add `_INTRA_LAYER_EXEMPTIONS` entries as needed; smoke scripts relative paths
   6. Acceptance test + CAPABILITIES + dep graph regen + `make check`
6. **Edge cases / failure modes** —
   - Rule 7 (builder's last FROM resolves to forge-rooted image): still satisfied because builders dogfood `pre-builder/<lang>-slim-trixie` (post-FG-065 + FG-070).
   - Rule 6 intra-tier: builders are L2 — exempt from "pre-builder may not FROM pre-builder" since they aren't pre-builders. Already scoped.
   - Downstream consumers using `$FORGE_BUILDER_REF` (without lang suffix): this is the python-legacy pattern. Preserve the rename to `BUILDER_PYTHON_REF` across all 8 Dockerfiles including base/*.
7. **Out of scope** — No builder version bumps. No new builder. No consumer migration beyond ARG rename. FG-073 (nginx-scratch-alpine) + FG-074 (homelab consumer migration) stay separate.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_071_builder-tier-migration.sh`. All 9 sections pass + `make check` green + 4 `builder/*` tags live on GHCR after main-cron.
9. **Capabilities delivered or extended** —
   - NEW `build.builder-migrated` — All 4 forge-builders moved to `images/builder/<lang>-trixie/` + `ghcr.io/bboortz/builder/<lang>-trixie:<tag>`.
   - NEW `arch.builder-tier-images` — The L2 tier is physically encoded as the `builder/` directory + GHCR path prefix; no bare `forge-builder-*` paths remain in the fleet.

## Gherkin acceptance

```
Scenario: 4 builders live under images/builder/
  Given FG-071 has shipped
  When I run `ls images/builder/`
  Then I see python-trixie, go-trixie, node-trixie, zig-trixie
   And `ls images/` does NOT contain any forge-builder-* entry

Scenario: image.yaml declares explicit nested repo
  Given FG-071 has shipped
  When I read images/builder/<lang>-trixie/image.yaml
  Then it contains `repo: builder/<lang>-trixie`

Scenario: consumers use the new ARG names
  Given FG-071 has shipped
  When I grep "ARG FORGE_BUILDER" across every Dockerfile
  Then zero matches

Scenario: discover-images lists 4 builders under builder/
  Given FG-071 has shipped
  When I run `bash scripts/discover-images.sh builders`
  Then the include[] has 4 entries, all with image_dir starting with "builder/"

Scenario: dep graph L2 subgraph renders 4 builders with normalized ids
  Given FG-071 has shipped
  When I regenerate docs/image-dependency-graph.md
  Then the L2_builders subgraph lists builder_<lang>_trixie["builder/<lang>-trixie"]:::builder × 4

Scenario: verify-no-upstream-drift unchanged
  Given FG-071 has shipped
  Then scripts/verify-no-upstream-drift.sh has _EXPECTED=6 and passes
```

## References

- Plan: `docs/plan/FG-071-builder-tier-migration-plan.md`
- Red test: `tests/acceptance/test_FG_071_builder-tier-migration.sh`
- Capabilities: see `docs/CAPABILITIES.md`
- Parent: `docs/plan/tier-layering-model.md` §7 FG-071 subsection
