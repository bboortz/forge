# FG-084 — Plan: version hygiene (4 one-liner fixes from post-FG-083 audit)

**Story**: [`docs/stories/FG-084-version-hygiene.md`](../stories/FG-084-version-hygiene.md)
**Status**: ready → shipped
**Branch**: `feat/FG-084-version-hygiene`

## Design delta

Four edits across four files + two scan-baseline regens. Zero image-shape changes; zero dependency changes.

| # | File | Change |
|---|---|---|
| 1 | `images/base/scratch-trixie/image.yaml` | `tag: "0.2"` → `tag: "0.3"` |
| 3 | `images/pre-builder/zig-slim-trixie/PROMISES.yaml` | `version: "0.2.0"` → `version: "0.2"` |
| 4 | `images/psitransfer-slim-trixie/Dockerfile` | `ARG PSITRANSFER_VERSION=latest` → `ARG PSITRANSFER_VERSION=""` + resolver check `… = ""` |
| 5a | `images/base/scratch-trixie/scan-baseline.json` | regenerate via `make scan-baseline-update` |
| 5b | `images/base/python-scratch-trixie/scan-baseline.json` | regenerate via `make scan-baseline-update` |

## Alternatives rejected

- **Bulk refresh all 18 stale scan-baselines in this PR** — 18× build+scan locally is 1-2 hours; adds no new coverage (daily cron re-scans everything live). Scope creep.
- **Rename PROMISES `image:` field collisions (audit item 2)** — 10 files + resolver audit; deserves own FG. Deferred.
- **Add a schema-version lint for PROMISES `version:`** — over-eager; `verify-promises-version-bump.sh` already catches the real drift class (promises change but version doesn't). Adding a "3-digit disallowed" rule is premature.
- **Push `tag: "0.3"` publish without the PR** — would skip the usual DD-TGD cycle for a contract change.

## Breaking changes

None. Consumers using `SCRATCH_BASE_REF=ghcr.io/bboortz/base/scratch-trixie:latest` continue to resolve unchanged. The new `:0.3` tag joins the family without displacing `:0.2` (which stays a frozen alias to the old digest). `psitransfer` resolver behaviour is identical (empty-default + the resolve-from-GitHub path).

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI. Local build + scan-baseline-update for the two base images. No image-shape changes.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` publishes the new `base/scratch-trixie:0.3` family + refreshed digests for the other 3 edits. Daily cron handles re-sign of everything else.

## Tooling updates

None. FG-083's `verify-promises-version-bump.sh` catches any future drift of this class.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| (1) `image.yaml tag:` = "0.3" | test §1 | ✅ |
| (3) PROMISES version normalized to 2-digit | test §2 | ✅ |
| (4) PSITRANSFER_VERSION default "" | test §3 | ✅ |
| (5) 2 scan-baselines generated_at < 24h old | test §4 | ✅ |
| `make test-fast` green | pre-ship | ✅ |
| `verify-promises-version-bump` no-ops (tag-only, not PROMISES, change) | pre-ship | ✅ |
