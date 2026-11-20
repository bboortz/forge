---
id: FG-070
slug: pre-builder-tier-migration
status: in-progress
owner: bboortz
created: 2026-11-20
---

# FG-070 — pre-builder/ tier migration

Move the 7 L1 pre-builders into `images/pre-builder/<name>/` per tier-plan §O (post-FG-069 continuation). GHCR paths migrate to `ghcr.io/bboortz/pre-builder/<name>:<tag>`. 8 consumer `ARG *_SLIM_REF` defaults in forge Dockerfiles flip to the new paths. **Homelab coordination held at FG-074** — homelab's 7 python bots reference `ghcr.io/bboortz/python-slim-trixie` as a Dockerfile `FROM` parent and need the paired flip; FG-074 captures that work as a separate story per user direction.

Leaf names stay unchanged (`python-slim-trixie` stays `python-slim-trixie`) — the tier prefix adds the semantic.

## 9 canonical answers

1. **Who** — Forge maintainer + homelab operator (paired FG-074 PR). All 8 forge internal consumers flip in this PR.

2. **When** — Fires at merge; next release promotes main; daily cron publishes `ghcr.io/bboortz/pre-builder/*` under the new paths. Homelab's FG-074 PR runs on its own cadence after that.

3. **What success looks like**:
   - 7 directories moved: `images/pre-builder/{debian-slim-trixie,debian-slim-sid,go-slim-trixie,node-slim-trixie,python-slim-trixie,ubuntu-slim-noble,zig-slim-trixie}/`.
   - Old flat paths gone.
   - Each has explicit `repo: pre-builder/<name>` in image.yaml (mirror/+base/ convention).
   - 8 forge Dockerfiles' ARG defaults flip to the new path: `UBUNTU_SLIM_NOBLE_REF`, `ZIG_SLIM_REF` (in forge-builder-zig-trixie), `PYTHON_SLIM_REF`, `NODE_SLIM_REF` (in forge-builder-node-trixie + uptime-kuma-slim-trixie), `GO_SLIM_REF`, `DEBIAN_SLIM_REF` (in cadvisor + ipmi-exporter-slim + pre-builder/zig-slim-trixie).
   - Tooling updated: `verify-dockerfile-conformance.py` + `image_from_graph.py` `_PRE_BUILDERS` sets, `discover-images.sh` `_PRE_BUILDERS`, `build-image.sh` resolution paths, `verify-no-upstream-drift.sh` nested glob, `scripts/_upstream_sources.py` zig consumer canonical path.
   - PROMISES.yaml preflight paths updated in all 7 pre-builders' contracts + consumer EXPECTATIONS.
   - `_INTRA_LAYER_EXEMPTIONS` entry for zig→debian updated to canonical paths.
   - `_check_language_family_invariant` expects sibling at `pre-builder/<lang>-slim-trixie` (not flat).
   - Dep graph regenerated: all 7 pre-builders emit as `pre-builder_<leaf>["pre-builder/<name>"]:::prebuilder` nodes under L1.
   - FG-064 §3 node-existence test's id translation already handles the dash+slash case (fixed in FG-069).
   - FG-065, FG-061, FG-072 adjacent tests' pre-builder path assertions updated.
   - `_EXPECTED` in verify-no-upstream-drift stays at **6** (ARG-indirect FROM doesn't change literal-grep count; one exception: zig-slim-trixie's FROM is ARG-indirect into pre-builder/debian-slim-trixie, not a literal upstream).
   - CAPs: NEW `build.pre-builder-migrated` + `arch.pre-builder-tier-images`; EXT `build.pre-builder-tier`, `image.forge-rooted-slim-bases`.
   - Memory: `memory/docker-standard.md` reflects nested paths.

4. **Urgency** — Prerequisite for FG-071 (builder/ migration). Also the trigger for the paired FG-074 homelab PR.

5. **Happy path**:
   1. Branch `feat/FG-070-pre-builder-tier-migration` off dev.
   2. `git mv` × 7.
   3. Add `repo: pre-builder/<name>` to each image.yaml.
   4. Update 8 consumer ARG defaults + scripts + PROMISES + EXPECTATIONS preflight paths.
   5. Regen dep graph; run `make test-fast` + relevant acceptance tests.
   6. PR → CI → merge.
   7. release.yml → publish-pre-builders tier publishes to new paths.
   8. FG-074 (homelab) PR merges separately.

6. **Edge cases / failure modes**:
   - **Explicit repo: field**: nested dirs REQUIRE `repo: pre-builder/<name>` (same as base/ + mirror/). Without it, `image_yaml_repo` returns the leaf — build-image.sh would tag `forge-local/python-slim-trixie:latest` not `forge-local/pre-builder/python-slim-trixie:latest`. Consumers can't resolve.
   - **PROMISES preflight paths**: all 7 pre-builders' + consumer EXPECTATIONS files reference `images/<name>/tests/<script>` for the old path. Must rewrite to `images/pre-builder/<name>/tests/<script>`.
   - **Mermaid node id normalization**: `pre-builder/debian-slim-trixie` → `pre-builder_debian_slim_trixie`. The L1 subgraph emitter now uses `<id>["<label>"]:::prebuilder` form for nested paths (mirrors L3 baseline + L0.5 mirror shape). FG-064 §3 regex already handles both `<id>:::` and `<id>["label"]:::`.
   - **verify-no-upstream-drift glob**: old `images/*/Dockerfile` only-flat glob needed widening to `images/*/Dockerfile images/*/*/Dockerfile`. _EXPECTED stays at 6.
   - **language-family invariant**: `_check_language_family_invariant` was pinned to flat sibling `<lang>-slim-trixie`; now expects nested `pre-builder/<lang>-slim-trixie`.
   - **GHA artifact name**: PR #128's upstream fix (safe_name replacing `/` with `_`) already landed via FG-069 fallout. New pre-builder paths won't retrip the `/`-in-artifact-name bug.
   - **Homelab timing**: FG-074 held — homelab's 7 python bots will pull STALE `ghcr.io/bboortz/python-slim-trixie:latest` until their PR merges. Acceptable (same workaround window as beaconry/FG-069).

7. **Out of scope**:
   - Moving builders (`forge-builder-*-trixie`) — that's FG-071 (biggest blast).
   - Renaming leaf names (`python-slim-trixie` stays `python-slim-trixie`; tier prefix carries the layer semantic).
   - Deleting the legacy `ghcr.io/bboortz/<name>` repos — they just stop being updated.
   - Homelab's 7 bot Dockerfile flip — FG-074 territory.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `build.pre-builder-migrated` — L1 pre-builders now live at `images/pre-builder/<name>/` with GHCR paths `ghcr.io/bboortz/pre-builder/<name>:<tag>`. Explicit `repo:` in image.yaml. 7 current members (debian trixie + sid, go, node, python, ubuntu noble, zig).
   - NEW `arch.pre-builder-tier-images` — architectural invariant: every `pre-builder/` image has thin `apt-upgrade` + CA + dumb-init layer on an upstream OS base, NO application payload, keeps shell + apt, and is consumed by ≥1 forge image (L2 builder dogfood, L4 slim runtime, or L3 base).
   - EXT `build.pre-builder-tier` — formalized post-FG-070; the `publish-pre-builders` CI tier's matrix now walks `images/pre-builder/*/image.yaml`.
   - EXT `image.forge-rooted-slim-bases` — all 7 bases live under the new path.

## Gherkin acceptance

```
Scenario: 7 pre-builders moved to pre-builder/
  Given current HEAD
  Then images/pre-builder/{debian-slim-trixie,debian-slim-sid,go-slim-trixie,
       node-slim-trixie,python-slim-trixie,ubuntu-slim-noble,zig-slim-trixie}/
       all exist
  And images/{debian-slim-trixie,...}/ (flat) do NOT exist

Scenario: explicit repo: fields present
  Given every images/pre-builder/<name>/image.yaml
  Then it contains `repo: pre-builder/<name>`

Scenario: 8 consumer ARG defaults updated
  Given every Dockerfile in the fleet
  Then no ARG *_REF default references `ghcr.io/bboortz/<leaf>` for any
       of the 7 pre-builders (must go through `ghcr.io/bboortz/pre-builder/`)

Scenario: discover-images.sh pre-builders returns 7 under the new path
  Given scripts/discover-images.sh pre-builders
  Then the matrix has exactly 7 entries
  And every image_dir starts with `pre-builder/`

Scenario: verify-no-upstream-drift stays at _EXPECTED=6
  Given scripts/verify-no-upstream-drift.sh
  Then it exits 0 AND _EXPECTED=6 is unchanged

Scenario: conformance lint green on the new fleet
  Given scripts/verify-dockerfile-conformance.py
  Then it exits 0
  And _check_language_family_invariant expects sibling at pre-builder/<lang>-slim-trixie

Scenario: dep graph L1 subgraph renders all 7 pre-builders with normalized ids
  Given regenerated docs/image-dependency-graph.md
  Then the L1 subgraph contains `pre-builder_debian_slim_trixie["pre-builder/debian-slim-trixie"]:::prebuilder`
  And similarly for the other 6 pre-builders
  And edges use the normalized id form

Scenario: FG-074 coordination noted
  Given current HEAD
  Then docs/stories/FG-074-homelab-pre-builder-consumer-migration.md exists
  And it references FG-070 as the trigger
  And FG-074 remains at `draft` status (NOT in-progress)

Scenario: memory + CAPs documented
  Given docs/CAPABILITIES.md
  Then it contains `### build.pre-builder-migrated`
  And it contains `### arch.pre-builder-tier-images`
  And both have Covered by: pointers
```

## References

- Plan: `docs/plan/FG-070-pre-builder-tier-migration-plan.md`
- Red test: `tests/acceptance/test_FG_070_pre-builder-tier-migration.sh`
- Tier model: `docs/plan/tier-layering-model.md` §O (pre-builder rename kept leaf names).
- Paired (held): `docs/stories/FG-074-homelab-pre-builder-consumer-migration.md` — 7 homelab bot Dockerfile updates. Merges after forge publishes the new paths.
