# FG-070 — Plan: pre-builder/ tier migration

**Story**: [`docs/stories/FG-070-pre-builder-tier-migration.md`](../stories/FG-070-pre-builder-tier-migration.md)
**Status**: in-progress
**Branch**: `feat/FG-070-pre-builder-tier-migration`

## Design delta

7 `git mv` renames + 8 consumer ARG default updates + script-wide walks for the new nested path. Leaf names stay unchanged — the tier prefix carries the semantic. Paired homelab PR is explicitly deferred to FG-074 per user direction.

## Alternatives rejected

- **Rename leaf names** (`python-slim-trixie` → `python-trixie`) — would cascade across every consumer Dockerfile AND homelab's 7 bots AND beaconry's paths AND ansible vars. Rejected: tier prefix is enough.
- **Open homelab PR in this FG** — user direction (pre-flight audit) → create story FG-074, don't solve in this run.
- **Bump `_EXPECTED` in drift guard** — the literal grep count unchanged (zig uses ARG-indirect FROM debian-slim-trixie; other 6 still FROM upstream literally). Stay at 6.

## Breaking changes

**Yes — user-visible GHCR path change** for the 7 pre-builder repos:
- `ghcr.io/bboortz/python-slim-trixie` → `ghcr.io/bboortz/pre-builder/python-slim-trixie`
- Same pattern for the other 6.

Internal consumers flip in this PR. External consumer (homelab) handled by FG-074 paired PR.

## Merge plan

- Lint + verify-* green
- `make test-acceptance` green (including FG-061, FG-065, FG-067, FG-068, FG-069, FG-072 which touch pre-builder refs)
- Dep graph regenerated + committed
- `verify-no-upstream-drift` still passes with `_EXPECTED=6`
- `_check_language_family_invariant` expects `pre-builder/<lang>-slim-trixie` siblings

## Rollout plan

1. Forge PR → `dev`.
2. release.yml → `main`.
3. Next daily cron publishes `ghcr.io/bboortz/pre-builder/*` (first-time publish at new paths).
4. FG-074 homelab PR merges after step 3.

## Shipping evidence

| Item | Pointer | Status |
|---|---|---|
| 7 renames + flat gone | `test_FG_070_...sh` §1 | ✅ |
| explicit repo: fields | §2 | ✅ |
| 8 ARG defaults | §3 | ✅ |
| discover-images | §4 | ✅ |
| drift _EXPECTED=6 | §5 | ✅ |
| conformance green | §6 | ✅ |
| dep graph L1 | §7 | ✅ |
| FG-074 coordination noted | §8 | ✅ |
| CAPs | §9 | ✅ |
