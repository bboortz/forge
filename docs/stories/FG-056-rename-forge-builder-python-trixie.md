---
id: FG-056
slug: rename-forge-builder-python-trixie
status: ready
owner: bboortz
created: 2026-11-15
---

# FG-056 — Rename `forge-builder-trixie` → `forge-builder-python-trixie`

Forge now has three builder-base images:

| Current name | FROM base | What it's for |
|---|---|---|
| `forge-builder-trixie` | `python-slim-trixie` (which is `python:3.14-slim-trixie`) | Debian apt-install builder — every Debian-apt-sourced scratch image's builder stage |
| `forge-builder-go-trixie` | `golang:1.27-trixie` | Go from-source builder |
| `forge-builder-node-trixie` | `node:24-trixie-slim` | Node from-source builder |

The existing `forge-builder-trixie` name does not tell the reader whether it's the Debian-only / Python / Go / Node variant — new maintainers have to grep the Dockerfile to find out. All three are Debian-based already; the discriminator is the pre-installed toolchain (python vs go vs node).

FG-056 renames the Python-rooted builder to make the family naming consistent:

```
forge-builder-trixie       → forge-builder-python-trixie
forge-builder-go-trixie    (unchanged)
forge-builder-node-trixie  (unchanged)
```

Pure refactor — zero behaviour change, zero consumer impact. No external consumers (this image is only `FROM`'d by Forge's own scratch builders). Must land **before** FG-057 (sid-pin curl/openssh/python in both builder images) so that FG-057's story + Dockerfile diff reference the final name.

## 9 canonical answers

1. **Who** — any future Forge maintainer (me, contributors, anyone reading a scratch image's Dockerfile and wondering what `FORGE_BUILDER_REF` resolves to). Prerequisite for FG-057's "sid-pin python-3.14 in the python builder" story being self-explanatory.

2. **When** — fires on every PR to `dev`: a reviewer should immediately see `forge-builder-python-trixie` in a scratch image's Dockerfile and know it brings the Python toolchain, differentiating from `forge-builder-go-trixie` / `forge-builder-node-trixie`.

3. **What success looks like**:
   - `images/forge-builder-python-trixie/` exists; `images/forge-builder-trixie/` does not.
   - Every Dockerfile that previously `FROM ghcr.io/bboortz/forge-builder-trixie:latest` now references `forge-builder-python-trixie:latest`.
   - `scripts/discover-images.sh` `_FORGE_BUILDERS` array includes `forge-builder-python-trixie` (not `forge-builder-trixie`).
   - `scripts/build-image.sh` auto-build + ref-resolution references the new name.
   - CI runs every acceptance test green on the renamed image.
   - GHCR publishes `ghcr.io/bboortz/forge-builder-python-trixie:latest` (new repo).
   - Legacy GHCR repo `ghcr.io/bboortz/forge-builder-trixie` is no longer updated (stays frozen at the last pre-FG-056 digest; auto-cleans up when garbage-collected after retention cutoff).
   - No code path still imports the old name.

4. **Urgency** — quality-of-life, but blocking FG-057 (sid-pins) because splitting the story cleanly requires the new name to already be in place.

5. **Happy path**:
   1. Branch `refactor/FG-056-rename-forge-builder-python` from `dev`.
   2. `git mv images/forge-builder-trixie images/forge-builder-python-trixie`.
   3. Update `images/forge-builder-python-trixie/PROMISES.yaml` `image:` field + any file-path refs inside.
   4. Update the 2 smoke scripts under `images/forge-builder-python-trixie/tests/` — IMAGE_NAME defaults + comments.
   5. Update every consumer Dockerfile's `ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest` → `forge-builder-python-trixie:latest` (7 Dockerfiles: scratch-base, python-scratch, nginx-scratch, mosquitto-scratch, redis-scratch, healthy-scratch — plus one `forge-local/forge-builder-trixie:0.1` fallback in scratch-base-trixie's Dockerfile).
   6. Update `scripts/discover-images.sh` `_FORGE_BUILDERS` array.
   7. Update `scripts/build-image.sh` auto-build block (grep-pattern + echo message).
   8. Update acceptance tests: `test_FG_025_forge-builder-trixie.sh` (rename + update assertions) + `test_FG_042_forge-rooted-slim-bases.sh` (updates `_FORGE_BUILDERS` assertion).
   9. Update `docs/CAPABILITIES.md` entries that name the image.
   10. Update `docs/image-dependency-graph.md` (node labels + consumer counts).
   11. Update `.github/workflows/build.yml` + `.github/workflows/ci.yml` comments.
   12. Red acceptance test `test_FG_056_rename-forge-builder-python-trixie.sh` encodes the invariants from #3 — passes after the refactor, fails if someone later reintroduces the old name.
   13. PR to `dev` → CI full-check → auto-merge on green.

6. **Edge cases / failure modes**:
   - **Historical plan docs under `docs/plan/FG-025-*`, FG-030/FG-034/FG-044/...-plan.md reference the old name.** Decision: **leave them as-is.** Plan docs capture the decision at the time it was made; retroactively rewriting them obscures history. The red test only asserts on live code paths (Dockerfiles, scripts, acceptance tests, CAPABILITIES.md).
   - **IDEAS.md references** — same treatment (historical idea text).
   - **Memory files (memory/*.md)** referencing the old name: update if the name is quoted as the authoritative example; leave the context phrases alone.
   - **`.make/stamps/forge-builder-trixie.stamp`** — stamp file keyed by old dir name. Harmless (next build re-stamps under new name); `make clean-stamps` wipes it.
   - **Legacy GHCR tag `ghcr.io/bboortz/forge-builder-trixie:latest` stops updating.** Signed digests from the last publish remain valid on GHCR indefinitely. No active external consumer — only Forge's own scratch builders FROM it, and this PR updates all of them atomically. Document in the PR body for any future auditor trying to understand why that repo is frozen.
   - **Short rollback window**: if the renamed builder has a bug caught post-merge, revert the merge commit; the previous builder image on GHCR is still viable.

7. **Out of scope**:
   - **Renaming `forge-builder-go-trixie` / `forge-builder-node-trixie`** — they already encode the toolchain. No change needed.
   - **Changing the image's contract** (PROMISES.yaml promises, tag family, size budget, ENV, USER).
   - **Updating historical plan docs** (FG-025, FG-030, FG-034, FG-042, FG-044, FG-050, etc.) — one-way diff that loses historical context.
   - **FG-057 sid-pins** — follows on this one.

8. **How do we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `build.shared-builder` — adopts the new name; description updated to clarify that the builder family splits by pre-installed toolchain (python / go / node).
   - EXT `build.pre-builder-tier` — references to the old name in the CAP description bumped to the new name.
   - No new CAPs.

## Gherkin acceptance

```
Scenario: new name is the only name in live code paths
  Given the dev branch at HEAD
  When grep -rn "forge-builder-trixie" --include="*.sh" --include="*.yml" --include="*.yaml" --include="Dockerfile" fires
    excluding docs/plan/*-plan.md, docs/plan/IDEAS.md, memory/*.md, docs/stories/FG-056-*.md
  Then no matches remain

Scenario: images/forge-builder-python-trixie builds end-to-end
  Given a clean build cache
  When scripts/build-image.sh forge-builder-python-trixie runs
  Then the image is tagged forge-local/forge-builder-python-trixie:0.1
  And its 2 existing smokes (smoke_has_syft.sh + smoke_builder_hygiene.sh) pass

Scenario: every consumer Dockerfile FROMs the new name
  Given every consumer Dockerfile declares ARG FORGE_BUILDER_REF
  When grep fires for "ARG FORGE_BUILDER_REF=" in images/*/Dockerfile
  Then every match ends with "forge-builder-python-trixie:latest"
    OR "forge-builder-python-trixie:0.1" (scratch-base-trixie's local fallback)
```
