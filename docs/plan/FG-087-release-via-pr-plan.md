# FG-087 — Plan: promote dev → main via auto-merge PR

**Story**: [`docs/stories/FG-087-release-via-pr.md`](../stories/FG-087-release-via-pr.md)
**Status**: in-progress → shipped
**Branch**: `feat/FG-087-release-via-pr`

## Design delta

Rewrite `.github/workflows/release.yml`:

Before (fails when main is protected):
```
dev CI green assertion
  → git merge --ff-only
  → git push origin main        ← rejected by protection
```

After:
```
dev CI green assertion
  → find-or-create PR dev → main
  → gh pr merge --auto --merge
  → poll PR until merged (or 10-min timeout)
  → report resulting main SHA
```

Trade-off: main's SHA is no longer `dev`'s SHA — it's a merge commit. The daily cron + consumers don't care about SHA lineage (they only care about main HEAD's tree). Acceptance test asserts the workflow no longer calls `git push origin main`.

## Alternatives rejected

- **Loosen main protection permanently** — defeats the point of having a protected branch.
- **Add a service account with admin override** — harder to audit; brittle.
- **Bypass via `--admin` flag on `gh pr merge`** — requires admin GH_TOKEN; current `${{ github.token }}` is not admin. Also makes the merge invisible to CODEOWNERS/reviews workflows.
- **Manual `loosen → push → restore` every release** — what FG-086 had to do. Error-prone, breaks on human error.

## Breaking changes

None for consumers. One internal consequence: `main` SHA ≠ `dev` SHA after promotion (main has an extra merge commit). Git history of dev is unchanged; main shows one additional "Merge pull request from dev" commit per release. No Forge tool depends on the SHA equality.

## Merge plan

- `tests/acceptance/test_FG_087_release-via-pr.sh` asserts the workflow's shape (red → green).
- `make test-fast` + PR CI acceptance matrix.
- One final loosen-push-restore cycle to land FG-087 itself (the fix landing via the old broken flow). Explicitly flagged as the last manual protection edit.

## Rollout plan

1. PR → dev (auto-merge on green CI).
2. One last manual `release.yml` run WITH the loosen-restore dance (same as FG-086's recovery).
3. FG-088+ and onward: `release.yml` promotes via PR; no manual steps.

## Tooling updates

- `.github/workflows/release.yml` — rewritten.
- `docs/specs/CAPABILITIES.md` — new CAP `ci.release-via-pr`.
- No Makefile / script changes.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: no direct push to main | `tests/acceptance/test_FG_087_release-via-pr.sh:§1` | ✅ |
| Scenario: dev-CI-green preserved | `§2` | ✅ |
| Scenario: reuses existing PR | `§3` | ✅ |
| CAP `ci.release-via-pr` | `test §1,§2,§3` + `docs/specs/CAPABILITIES.md#ci.release-via-pr` | ✅ |
| `make test-fast` green | pre-ship | ✅ |
