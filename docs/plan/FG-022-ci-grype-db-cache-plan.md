# FG-022 — Plan: grype DB cache in CI

**Story**: [`docs/stories/FG-022-ci-grype-db-cache.md`](../stories/FG-022-ci-grype-db-cache.md)
**Status**: in-progress
**Branch**: `feat/FG-021-ci-cache` (shared with FG-021)

## Design delta

Add to the three GHA workflows (`ci.yml`, `build.yml`, `nightly.yml`), in the step list before any grype invocation:

```yaml
- name: Current UTC day
  id: dt
  run: echo "day=$(date -u +%Y-%m-%d)" >> "$GITHUB_OUTPUT"

- name: Cache grype DB
  uses: actions/cache@v4
  with:
    path: ~/.cache/grype
    key: grype-db-${{ runner.os }}-${{ steps.dt.outputs.day }}
    restore-keys: |
      grype-db-${{ runner.os }}-
```

`restore-keys` without the date gives yesterday's cache on cache miss → grype runs a differential update (small) instead of full download (~20 MB).

## Alternatives rejected

- **Weekly rotation**: lets CVE DB drift up to 7 days; defeats scan-regression's point. Daily is the right cadence.
- **Cache grype binary itself**: grype install.sh runs once at setup; caching doesn't materially help.
- **Caching syft DB**: syft doesn't maintain a persistent CVE-DB-like store.

## Breaking changes

None. Additive.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| ci.yml has grype DB cache step | FG-022 acceptance § section 1 | ⏳ |
| build.yml + nightly.yml have it too | § 2 | ⏳ |
| Cache key uses current UTC date | § 3 | ⏳ |
| yamllint clean | implied by test-fast | ⏳ |
