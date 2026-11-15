---
id: FG-057
slug: build-image-filter
status: ready
owner: bboortz
created: 2026-11-15
---

# FG-057 — `build.yml` image filter for selective workflow_dispatch

A dev who has just updated a source repo (beaconry, prometheus, upstream alertmanager, etc.) wants to **rebuild + publish ONE Forge image** to GHCR immediately, without waiting for the 03:00 UTC cron and without triggering all 22 images.

Current state (shipped under FG-001 → FG-055): `build.yml` always builds every image in the four-tier matrix. A `workflow_dispatch` with no input runs identically to the nightly cron — 22 images, ~15–25 minutes (longer when heavy from-source builders like `prometheus-scratch-trixie` kick in).

Observed cost: this has been a pain point multiple times — a tiny fix to one image (e.g. FG-040, FG-053, FG-055) forces a full-fleet rebuild to get the published digest refreshed. The cost compounds for dev loops against externally-sourced images (beaconry-{hub,scout,telegram-mock}) where the only thing that changed is a line in a different repo.

FG-057 adds a `workflow_dispatch.inputs.images` filter. Default `all` preserves the cron contract; passing a dir name / comma list / glob rebuilds only the subset.

## 9 canonical answers

1. **Who** — any dev / maintainer with repository write access who has just updated a source dependency (externally-sourced like beaconry, or a from-source upstream like prometheus) and wants a fresh signed digest **now**, not at the next cron.

2. **When** — fires on `workflow_dispatch`. Daily cron keeps default (= `all`). Operator runs `gh workflow run build.yml -f images=beaconry-hub` and ~2 min later `ghcr.io/bboortz/beaconry-hub:latest` has a new digest (vs the current 15-25 min for the full fleet). Same for post-fix republishes (operator shipped a Forge PR for one image + wants to republish immediately).

3. **What success looks like**:
   - `workflow_dispatch` accepts an `images` input (default `all`).
   - `images=all` → rebuilds every image (identical to current behaviour; cron contract preserved).
   - `images=<name>` → rebuilds only that image + any transitive `depends_on:` ancestors that aren't already published.
   - `images=<name1>,<name2>` → rebuilds the comma-separated list (plus ancestors).
   - `images=<glob>` (e.g. `prometheus-*`, `*-scratch-trixie`) → rebuilds matching dirs (plus ancestors).
   - Nonexistent image name → workflow fails fast with a clear error.
   - When filtered, the dependency-aware matrix still produces the right tier ordering (pre-builders → builders → base → derivatives) — otherwise a downstream filter without its forge-builder ancestor would FROM a stale GHCR digest.
   - Daily cron runs with no input and behaves exactly as today.
   - Doc update in `README.md` § Operator-facing commands (or equivalent).

4. **Urgency** — quality-of-life + dev-loop productivity. Not security-material. Not blocking a shipping deadline. But observed-friction every time a single-image fix wants a non-cron publish.

5. **Happy path**:
   1. Branch `feat/FG-057-build-image-filter` from `dev`.
   2. Add `workflow_dispatch.inputs.images` to `build.yml`.
   3. `scripts/discover-images.sh` grows a `--filter <pattern>` flag (comma-list + glob support). Pattern applies AFTER tier-select so tier ordering is preserved.
   4. Dependency-closure resolution: when `images=X` is specified, recursively include any image Y where `X` appears in Y's `depends_on:` OR X's Dockerfile `FROM ${FORGE_BUILDER_REF}` resolves to Y. (Shortcut: let the filter be "match name" and rely on the operator to include transitive deps explicitly. Story defers the auto-closure to 5b if the auto-detection is too complex.)
   5. New `scripts/filter-images.sh` (or inline in discover-images.sh) that reads the filter + image.yaml graph to compute the effective set.
   6. Red acceptance test `test_FG_057_build-image-filter.sh`:
      - Invokes `scripts/discover-images.sh --filter "beaconry-hub" derivatives` and asserts the matrix contains only `beaconry-hub`.
      - Invokes with `--filter "prometheus-*"` and asserts it contains `prometheus-scratch-trixie` only (no cadvisor, no alertmanager, etc.).
      - Invokes with `--filter "all"` (default) → unchanged behaviour (every tier returns its full set).
      - Invokes with `--filter "nonexistent-image"` → nonzero exit + clear error.
   7. `make check-smart-strict` green locally.
   8. PR to `dev` → CI full-check → auto-merge on green.
   9. Dev-facing: `README.md` gets a one-line example under the "running the daily publish manually" section.

6. **Edge cases / failure modes**:
   - **Filter matches an image whose transitive FROM ancestor is also-filtered out** — e.g. `images=beaconry-hub` but the current forge-builder-python-trixie on GHCR is stale. This is a known-safe case: the base is already on GHCR (daily cron publishes it). Only a problem if the base has a breaking change in dev not yet merged — out of scope for this story (dev should trigger full build.yml for cross-tier changes).
   - **Glob matches zero images** — fail fast with "filter matched zero images".
   - **Filter is a comma-list where some entries don't exist** — fail with the list of unknown names.
   - **Pre-builders filter** — `images=debian-slim-trixie` rebuilds just the pre-builder. Downstream slim images continue to pull the existing GHCR digest. Operator takes responsibility for subsequent republishes.
   - **CI matrix fail-fast interaction** — `strategy.fail-fast: false` already handles partial-matrix failures. No change.
   - **Scheduled cron must be unaffected** — input default `all` + the cron trigger carries no inputs, so behaviour is identical to today. Covered by acceptance test.

7. **Out of scope**:
   - **Automatic dependency closure** — operator specifies exactly what they want. If they filter a scratch derivative without its slim/scratch-base-trixie ancestor and the ancestor has an uncommitted breaking change, the derivative build fails explicitly. Clean. Add dependency auto-closure as a future chore if the manual approach causes friction.
   - **PR / push trigger** — out of scope. PR CI still uses `ci.yml` (FG-017 smart-check), which already scopes to affected images.
   - **Parallel multi-arch** — arm64 is still a separate roadmap item; the filter operates on image names, not platforms.
   - **Multiple filter patterns via multiple `images: a images: b` lines** — only one `images` input (comma-list + glob are sufficient).

8. **How do we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.workflow-dispatch-image-filter` — operator can scope `workflow_dispatch` to a subset of images.
   - EXT `build.daily-publish` — explicitly documents that scheduled runs ignore the filter input (= `all`).
   - EXT `publish.matrix-auto-discovery` — matrix output now respects the filter.

## Gherkin acceptance

```
Scenario: daily cron publishes every image (unchanged behaviour)
  Given no workflow_dispatch input
  When the scheduled trigger fires at 03:00 UTC
  Then every image in images/ appears in exactly one tier's matrix

Scenario: operator filters to a single image
  Given workflow_dispatch input images=beaconry-hub
  When the discover job runs
  Then the derivatives matrix contains exactly one entry {image_dir: beaconry-hub}
  And the pre-builders, builders, and base matrices are empty JSON arrays

Scenario: operator filters by glob
  Given workflow_dispatch input images=prometheus-*
  When the discover job runs
  Then the derivatives matrix contains only the prometheus-* images
  And the pre-builders / builders / base matrices are empty

Scenario: operator filters by comma-separated list
  Given workflow_dispatch input images=beaconry-hub,beaconry-scout
  Then the matrix contains exactly those two entries

Scenario: operator passes a nonexistent image name
  Given workflow_dispatch input images=does-not-exist
  Then the discover job fails fast with "filter matched zero images"

Scenario: operator passes an empty-glob filter
  Given workflow_dispatch input images=xyz-*
  And no image directory matches
  Then the discover job fails fast with "filter matched zero images"
```
