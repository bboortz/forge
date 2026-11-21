# FG-085 — Plan: bump 5 pinned versions in runner-noble requirements-dev

**Story**: [`docs/stories/FG-085-runner-noble-deps-bump.md`](../stories/FG-085-runner-noble-deps-bump.md)
**Status**: ready → shipped
**Branch**: `feat/FG-085-runner-noble-deps-bump`

## Design delta

5 version bumps in a single file:

```diff
-ansible-lint==26.4.0
+ansible-lint==26.11.0
-fastapi==0.136.3
+fastapi==0.165.0
-PyJWT==2.15.0
+PyJWT==2.15.1
-pytest==9.0.3
+pytest==9.2.0
-ruff==0.15.22
+ruff==0.17.6
```

Snapshot date comment also bumps to 2026-11-21.

## Alternatives rejected

- **Bump only fastapi's patch (0.136.3 → 0.136.4)** — safer but leaves 29 minors of drift. If the upgrade is mostly safe, now is the right moment to pay down the gap.
- **Skip fastapi entirely** — leaves the biggest gap unaddressed. Smoke-test coverage is the gate; if it passes, ship.
- **Pin to specific sub-patches instead of latest** — extra bookkeeping with no benefit; OSV is clean for latest.

## Breaking changes

None expected. The `github-runner-noble:latest` tag re-resolves to a digest with newer pins; consumers that pull `:latest` automatically pick it up. Consumers pinning a specific digest are unaffected until they re-pin.

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI acceptance suite. Local build + smoke suite for `github-runner-noble` as the primary test.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` → publishes refreshed `ghcr.io/bboortz/github-runner-noble:latest` with new pins
4. Homelab PR (paired, out of scope here) resyncs its `requirements-dev.txt` to match

## Tooling updates

None.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| 5 lines bumped | `tests/acceptance/test_FG_085_runner-noble-deps-bump.sh:§1` | ✅ |
| Image builds + smokes green | §2 | ✅ |
| OSV advisories still zero | §3 | ✅ |
| `make test-fast` green | pre-ship | ✅ |
