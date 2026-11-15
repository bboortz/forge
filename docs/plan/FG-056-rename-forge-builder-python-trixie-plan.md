---
id: FG-056
slug: rename-forge-builder-python-trixie
story: ../stories/FG-056-rename-forge-builder-python-trixie.md
---

# FG-056 plan — rename `forge-builder-trixie` → `forge-builder-python-trixie`

Story: [FG-056](../stories/FG-056-rename-forge-builder-python-trixie.md). This plan enumerates the edits needed to carry the rename through the whole live codebase, the files intentionally left as-is, and the merge order.

## Edit catalogue

### 1. Image directory rename

```
images/forge-builder-trixie/        → images/forge-builder-python-trixie/
```

Executed via `git mv` to preserve history.

### 2. Internal metadata

- `images/forge-builder-python-trixie/PROMISES.yaml`
  - `image: forge-builder-trixie` → `image: forge-builder-python-trixie`
  - Test file paths (if any absolute paths): bump to new dir.
- `images/forge-builder-python-trixie/image.yaml` — no change needed; repo is derived from the dir name.
- `images/forge-builder-python-trixie/tests/smoke_has_syft.sh`
- `images/forge-builder-python-trixie/tests/smoke_builder_hygiene.sh`
  - `IMAGE_NAME` default from `forge-builder-trixie` → `forge-builder-python-trixie`.
  - Comments naming the image.

### 3. Consumer Dockerfiles (ARG FORGE_BUILDER_REF)

Seven Dockerfiles currently resolve `FORGE_BUILDER_REF` against `ghcr.io/bboortz/forge-builder-trixie:latest` or `forge-local/forge-builder-trixie:0.1`:

- `images/scratch-base-trixie/Dockerfile` (local fallback `forge-local/forge-builder-trixie:0.1` + ghcr ref)
- `images/python-scratch-trixie/Dockerfile`
- `images/nginx-scratch-trixie/Dockerfile`
- `images/mosquitto-scratch-trixie/Dockerfile`
- `images/redis-scratch-trixie/Dockerfile`
- `images/healthy-scratch-trixie/Dockerfile`

All flip to `ghcr.io/bboortz/forge-builder-python-trixie:latest` (+ `forge-local/forge-builder-python-trixie:0.1` for scratch-base's fallback).

### 4. Scripts

- `scripts/discover-images.sh`:
  - `_FORGE_BUILDERS=(forge-builder-trixie forge-builder-go-trixie forge-builder-node-trixie)`
    →
  - `_FORGE_BUILDERS=(forge-builder-python-trixie forge-builder-go-trixie forge-builder-node-trixie)`.
- `scripts/build-image.sh`:
  - Auto-build block: comment + echo string updated.
  - Ref-resolution block: `_FORGE_BUILDER_DIR` + `_FORGE_BUILDER_YAML` + `_FORGE_BUILDER_TAG` + `FORGE_BUILDER_REF` lines updated.
  - `--build-arg FORGE_BUILDER_REF=` line passes the new ref value.

### 5. Acceptance tests

- `tests/acceptance/test_FG_025_forge-builder-trixie.sh` — rename to `test_FG_025_forge-builder-python-trixie.sh`. Update inline assertions (`images/forge-builder-trixie/...` → new path, tag + repo references).
- `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh` — updates the `_FORGE_BUILDERS` array check + the "pre-builders feed into builders" assertion names.
- `tests/acceptance/test_FG_056_rename-forge-builder-python-trixie.sh` — new, encodes the Gherkin scenarios from the story.

### 6. CAPABILITIES.md

Entries that name the image:
- `build.shared-builder`: update description + Covered-by paths.
- `build.pre-builder-tier`: update dependency flow description.
- `image.forge-rooted-slim-bases`: mentions `forge-builder-trixie` in consumer list.

### 7. Image dependency graph

`docs/image-dependency-graph.md` — update node labels (`FBT` node + its FG-025 annotation) + section 3 "Debian-world builder" bullet + section 8 "ipmi-exporter uses both builders" note.

### 8. CI workflow comments

- `.github/workflows/build.yml` — publish-builders tier comment update.
- `.github/workflows/ci.yml` — no code changes expected (matrix-driven); if there are inline job names, those bump too.

## Intentionally NOT edited

- **`docs/plan/FG-NNN-*-plan.md` (all historical plan docs)** — kept verbatim. These captured decisions at the time they were made. Rewriting them erases history + introduces a one-way diff that confuses future readers of commit archaeology.
- **`docs/plan/IDEAS.md`** — same reasoning for the shipped/promoted entries.
- **`docs/stories/FG-NNN-*.md` for shipped stories referencing the old name** — same reasoning (except this story, which naturally uses both names to describe the rename).
- **`memory/*.md`** — leave context phrases alone. Only touch if a memory quotes the name as the authoritative current example (there's one reference in `memory/scratch-closures.md`'s derivative composition pattern that may need a touch, verified during execution).

## Merge order

1. Branch from `dev`.
2. Edit everything above atomically (one commit — pure refactor).
3. Local build + full acceptance suite (can skip the long-tail via `check-smart-strict` — refactor only touches builder + consumers + tests).
4. PR to `dev`.
5. On green CI, auto-merge.
6. Release workflow promotes dev → main.
7. Daily publish creates `ghcr.io/bboortz/forge-builder-python-trixie:latest` for the first time + stops updating the old repo.
8. FG-057 (sid-pins) branches off dev with the new names already in place.

## Shipping evidence (filled before commit)

| Lens | Item | Status |
|------|------|--------|
| Gherkin coverage | Scenario 1 (grep returns no matches) | ⏳ pending test |
| Gherkin coverage | Scenario 2 (image builds) | ⏳ |
| Gherkin coverage | Scenario 3 (every consumer FROMs new name) | ⏳ |
| Self-consistency | FG-056 red test written and passes post-refactor | ⏳ |
| Self-consistency | FG-025 renamed + still passes (same semantics) | ⏳ |
| Self-consistency | FG-042 pre-builders + builders tier assertions match | ⏳ |
| Build symmetry | GHCR publishes new repo; old repo stops | ⏳ (daily cron after main promote) |
| No breaking changes to external consumers | Internal-only builder; verified via grep across homelab + beaconry | ✅ confirmed via search |
