---
id: FG-087
slug: release-via-pr
status: shipped
owner: bboortz
created: 2026-11-22
---

# FG-087 — Promote dev → main via auto-merge PR (not direct push)

Forge's `main` branch is protected with a required status check `resolve-pr`
that only attaches to pull requests (app 15368). The current `release.yml`
fast-forwards main from dev with a **direct push** — which the protection
rejects, because the pushed SHA has no `resolve-pr` check-run. FG-086
discovered this the hard way: the FG-086 promotion required a temporary
loosen-push-restore dance on the branch protection.

FG-087 rewrites `release.yml` to promote via a short-lived pull request
(dev → main) that auto-merges once CI goes green. Main stays protected;
promotions are automatic; no more manual protection gymnastics.

## 9 canonical answers

1. **Who** — Forge maintainer triggering `release.yml`; CI/release bot; any future operator who only knows "click the Release workflow button".
2. **When** — Every manual promotion. Happens roughly once per shipped FG. Also matters any time branch protection on main gets stricter (we don't want to break again).
3. **What success looks like** —
   - `gh workflow run release.yml` creates a dev→main PR.
   - PR gets `resolve-pr` + any other required checks.
   - Workflow waits for required checks to pass, then auto-merges the PR.
   - Main reaches the dev tree (same content; SHA may be a new merge commit — acceptable).
   - No manual branch-protection edits ever required again.
4. **Urgency** — Workflow friction; not security-critical. Correctness-ish: a broken promotion blocks the daily cron from picking up new recipes.
5. **Happy path** —
   1. Operator pushes work through PR → dev; dev CI goes green.
   2. Operator clicks `release.yml` → workflow_dispatch.
   3. Workflow asserts "Acceptance aggregate (all green)" + "Lint & verify" are green on dev HEAD (unchanged from current).
   4. Workflow checks if an open PR `dev → main` already exists; if yes, reuses it; else creates one.
   5. Workflow enables auto-merge (`gh pr merge --auto --merge`) with the admin-flag fallback disabled by default.
   6. GitHub waits for `resolve-pr` + any other required checks on the PR; auto-merges when green.
   7. Workflow's final step polls the PR until merged (or timeout) and reports the resulting main SHA.
6. **Edge cases / failure modes** —
   - **Dev CI not green yet**: existing pre-flight assertion catches this; workflow aborts.
   - **Required check never fires on PR**: workflow times out after ~10 min; reports the stalled check names.
   - **PR already exists from a prior release run that was never merged**: reuse it (don't open a duplicate).
   - **Merge-commit changes the main SHA shape**: documented as a non-issue — daily cron publishes from main HEAD, doesn't care about SHA lineage. The one place that DID care (`verify-dep-graph-fresh` etc.) is dev-only.
   - **Auto-merge disabled on repo**: pre-flight check returns clear error.
7. **Out of scope** —
   - Changing the required check set on main (it stays as whatever ops configure).
   - Changing the trigger model (still `workflow_dispatch`, still manual).
   - Signing releases / tagging releases / changelog generation.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_087_release-via-pr.sh`. Shell-level assertions over the updated workflow file (YAML shape + step IDs + no `git push origin main`).
9. **Capabilities delivered or extended** —
   - EXT `publish.main-branch-promotion` — the promotion mechanism changes from direct push to auto-merge PR. (If this CAP doesn't exist yet, this FG creates it.)
   - NEW `ci.release-via-pr` — `release.yml` uses a PR + auto-merge to reach main, so main's branch protection is respected by the automation.

## Gherkin acceptance

```
Scenario: release.yml no longer does a direct push to main
  Given FG-087 has shipped
  Then .github/workflows/release.yml contains no `git push origin main`
   And it contains `gh pr create --base main` or equivalent
   And it enables auto-merge via `gh pr merge --auto`

Scenario: pre-flight dev-CI-green assertion preserved
  Given FG-087 has shipped
  Then release.yml still asserts Acceptance aggregate (all green) + Lint & verify

Scenario: reuses an existing open release PR
  Given FG-087 has shipped
  Then release.yml checks for an existing open dev→main PR before creating one
```

## References

- Plan: `docs/plan/FG-087-release-via-pr-plan.md`
- Red test: `tests/acceptance/test_FG_087_release-via-pr.sh`
- Capabilities: see `docs/specs/CAPABILITIES.md`
