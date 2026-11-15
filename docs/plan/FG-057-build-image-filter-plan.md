---
id: FG-057
slug: build-image-filter
story: ../stories/FG-057-build-image-filter.md
---

# FG-057 plan — `build.yml` image filter for selective workflow_dispatch

Story: [FG-057](../stories/FG-057-build-image-filter.md). Design delta + implementation blueprint.

## Design delta

### Current

```yaml
on:
  schedule: [{cron: "0 3 * * *"}]
  workflow_dispatch: {}
```

`discover` emits four tier matrices; every workflow invocation rebuilds all 22 images.

### Target

```yaml
on:
  schedule:
    - cron: "0 3 * * *"
  workflow_dispatch:
    inputs:
      images:
        description: 'Which images to rebuild (default: all). Accepts dir name, comma list, or glob.'
        type: string
        default: 'all'
```

`discover` job reads `${{ inputs.images || 'all' }}` (the `|| 'all'` falls back for the `schedule` trigger that carries no inputs) and passes it to `scripts/discover-images.sh` as a `--filter <pattern>` flag.

### Filter semantics

| Input | Matched set |
|---|---|
| `all` (or empty, or scheduled cron) | every image under `images/*/` |
| `beaconry-hub` | just `images/beaconry-hub/` |
| `beaconry-hub,beaconry-scout` | both listed dirs |
| `prometheus-*` | shell glob against image dir names |
| `*-scratch-trixie` | glob — every scratch image |
| `does-not-exist` | fail fast with nonzero exit |

The filter applies **after** tier-select — so `discover-images.sh pre-builders --filter prometheus-*` produces empty (no pre-builders match the pattern), which is correct behaviour.

### Error handling

- Zero matches → `discover` fails with a clear stderr message ("filter matched zero images").
- Unknown names in a comma list → fail with the list of unknown names.

### No auto-dependency-closure (out of scope per story)

If the operator filters to a scratch derivative whose forge-builder base has an uncommitted breaking change in `dev`, the build fails loudly with a clear error. Operator can rebuild the full fleet by omitting the filter. Keeps this story's scope tight; auto-closure is a future refinement if the manual approach causes friction.

## Edit catalogue

### 1. `.github/workflows/build.yml`

- Add `workflow_dispatch.inputs.images` with `default: all`.
- `discover` job reads `${{ inputs.images || 'all' }}` into a `FILTER` env.
- Each `scripts/discover-images.sh <mode>` invocation becomes `scripts/discover-images.sh <mode> --filter "${FILTER}"`.

### 2. `scripts/discover-images.sh`

- Accept `--filter <pattern>` positional-style option after the mode arg.
- Pattern grammar: `all` | `<name>` | `<name1>,<name2>,...` | shell glob.
- Implementation: parse `--filter`, split on commas, for each token either exact-match-dir-exists or glob-match against `images/*/`. Union the results. Fail if zero matches.
- The existing tier-select (pre-builders / builders / base / derivatives) remains the first filter; `--filter` applies after.

### 3. New red acceptance test

`tests/acceptance/test_FG_057_build-image-filter.sh` exercises every Gherkin scenario against `scripts/discover-images.sh` directly (no need to spin up the GHA runner).

### 4. README update

One paragraph under "Running the daily publish manually" in README.md with concrete examples:

```bash
# Publish everything (daily cron default)
gh workflow run build.yml

# Rebuild + publish just one image after a source-repo bump
gh workflow run build.yml -f images=beaconry-hub

# Rebuild + publish a slice
gh workflow run build.yml -f images=prometheus-*
gh workflow run build.yml -f images=beaconry-hub,beaconry-scout
```

### 5. CAPABILITIES.md

- NEW: `build.workflow-dispatch-image-filter` section.
- EXT: `build.daily-publish` + `publish.matrix-auto-discovery` get a one-line extension note.

## Merge order

1. Branch from `dev`.
2. All edits in one commit (story + plan + red test + Dockerfile + script + README + CAPABILITIES).
3. CI full-check validates the matrix outputs under filter are correct.
4. Auto-merge on green.
5. **No need to trigger a manual publish after merge** — the filter isn't exercised by the daily cron. Next operator-triggered workflow_dispatch exercises it for the first time.

## Shipping evidence (filled before commit)

| Lens | Item | Status |
|------|------|--------|
| Gherkin coverage | Scenario 1 (unchanged cron behaviour) | ⏳ |
| Gherkin coverage | Scenario 2 (single image) | ⏳ |
| Gherkin coverage | Scenario 3 (glob) | ⏳ |
| Gherkin coverage | Scenario 4 (comma list) | ⏳ |
| Gherkin coverage | Scenario 5 (nonexistent name) | ⏳ |
| Gherkin coverage | Scenario 6 (empty glob) | ⏳ |
| Build symmetry | Daily cron still publishes every image | ✅ unchanged workflow behaviour when input defaults to `all` |
| Self-consistency | NEW CAP registered + bidirectional link | ⏳ |
| Self-consistency | README documents the flag | ⏳ |
