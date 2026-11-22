---
id: FG-089
slug: sh029-branching-convergence
status: ready
owner: @benni
created: 2026-11-22
---

# FG-089 — Adopt feat/* → dev → main convergence (default branch = dev)

Umbrella is in shepherd: [SH-029 fleet branching convergence](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-029-fleet-branching-convergence.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23). This FG-089 is the forge-side ledger entry so the per-repo plan-doc + story-doc conventions stay intact.

## 9 canonical answers

1. **Who** — shepherd's `--verify-contract` (SH-017) + forge contributors who expect `gh pr create` to target `dev` by default.
2. **When** — once per repo, as a Makefile+workflow PR followed by a repo-settings flip.
3. **What success looks like** — `.github/workflows/ci-release.yml` dispatches on `dev`, runs FF+tag, pushes main. `make ci-release` calls `ci-release-promote`. Post-merge: `gh repo view --json defaultBranchRef` returns `dev`.
4. **Urgency** — correctness (uniform contract shape across the fleet unlocks SH-017 verifier).
5. **Happy path** — merge this PR → operator flips default → dispatch ci-release.yml once as a no-op smoke → confirm tag + FF.
6. **Edge cases** — existing nightly `build.yml` + image publishing untouched; co-exist with the new ci-release path.
7. **Out of scope** — retiring nightly `build.yml`; promote-by-digest (SH-022); any workflow YAML changes besides adding the new file.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - EXT `shepherd.branching-convergence` — forge row flips to green in the shepherd fleet-branching-convergence tracker (upstream CAP `dev-cycle.fleet.branching-convergence`).

## Gherkin acceptance

```gherkin
Scenario: ci-release-promote mutates git only on dev
  Given the forge repo at HEAD
  When  `make ci-release-promote` runs on a feat/* branch
  Then  exit code is 1
  And   stderr contains "must run on 'dev'"

Scenario: ci-release.yml checks out dev on dispatch
  Given the forge repo at HEAD
  Then  .github/workflows/ci-release.yml has `ref: dev` on the checkout step

Scenario: existing release flow preserved
  Given the forge repo at HEAD
  Then  `check-strict` body is byte-identical to pre-PR
  And   `build.yml` (nightly publish) is untouched
```

## Plan doc

[`docs/plan/FG-089-sh029-branching-convergence-plan.md`](../plan/FG-089-sh029-branching-convergence-plan.md).
