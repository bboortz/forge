---
id: FG-022
slug: ci-grype-db-cache
status: shipped
owner: bboortz
created: 2026-11-07
---

# FG-022 — grype DB cache in CI

Every grype invocation downloads/updates its CVE DB (~20 MB). In a full-check CI run, scan-regression runs grype **once per affected image** (up to 8 times). Fresh runner = 8× DB download = ~30-60s of unneeded network work.

Fix: `actions/cache@v4` keyed on a date stamp (daily refresh) persists `~/.cache/grype` across CI runs.

### Shape

```yaml
- name: Cache grype DB
  uses: actions/cache@v4
  with:
    path: ~/.cache/grype
    key: grype-db-${{ runner.os }}-${{ steps.date.outputs.day }}
    restore-keys: grype-db-${{ runner.os }}-

- name: date
  id: date
  run: echo "day=$(date -u +%Y-%m-%d)" >> $GITHUB_OUTPUT
```

Daily rotation ensures freshness; `restore-keys` falls back to yesterday's DB if today's isn't yet cached (self-updating on first use each day).

## 9 canonical answers (compressed)

1. **Who** — CI runner's grype calls; developers waiting on CI.
2. **When** — every scan-regression invocation in CI.
3. **Success** — `actions/cache` restores `~/.cache/grype`; grype uses cached DB instead of downloading; measured 30-60s drop per full-check CI.
4. **Urgency** — small but trivial win.
5. **Happy path** — add the 10-line cache step to `.github/workflows/{ci,build,nightly}.yml` before any `grype` call.
6. **Edge cases** —
   - Cache miss (first run of the day): grype downloads normally; subsequent CI jobs today benefit.
   - DB corruption: unlikely; mitigated by daily rotation.
   - GHA cache size limits (10 GB per repo): 20 MB × 7 days of rotations = ~140 MB. Trivial.
7. **Out of scope** — syft DB cache (syft doesn't have a comparable persistent DB).
8. **Done** — FG-022 acceptance green + workflow YAML lints clean.
9. **Capabilities**:
   - EXT `tooling.ci-build-cache` (shared with FG-021 — CI build cache umbrella)

## Gherkin acceptance

```
Scenario: ci.yml caches ~/.cache/grype
  Given .github/workflows/ci.yml
  Then the full-check job has an actions/cache step for ~/.cache/grype
   And the key includes the current UTC date

Scenario: build.yml + nightly.yml have the same cache
  Given .github/workflows/{build,nightly}.yml
  Then both have the grype DB cache step
```

## References

- Plan: [`docs/plan/FG-022-ci-grype-db-cache-plan.md`](../plan/FG-022-ci-grype-db-cache-plan.md)
- Red test: [`tests/acceptance/test_FG_022_ci-grype-db-cache.sh`](../../tests/acceptance/test_FG_022_ci-grype-db-cache.sh)
- Pairs with: FG-021 — shipped in the same PR
