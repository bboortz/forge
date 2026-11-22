---
id: FG-088
slug: sh019-contract-adoption
status: ready
owner: @benni
created: 2026-11-22
---

# FG-088 — Adopt shepherd dev-cycle contract

Umbrella is in shepherd: [SH-019 (fleet contract rollout)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-019-fleet-contract-rollout.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23). This FG-088 is the forge-side ledger entry so the per-repo plan-doc + story-doc conventions stay intact.

## 9 canonical answers

1. **Who** — shepherd's `--verify-contract` (SH-017); forge contributors who want a uniform make-target vocabulary across the fleet.
2. **When** — once, as a Makefile append + plan doc.
3. **What success looks like** — `make -n <each-contract-target>` resolves to real forge work; existing `test-fast` / `check` / `check-strict` unchanged; `shepherd-bump --verify-contract` will pass.
4. **Urgency** — correctness (`.shepherd.yml` points at `make test` which didn't exist; now it does).
5. **Happy path** — merge PR → next shepherd-bump run (scope expanded in SH-017) passes verification.
6. **Edge cases** — none; purely additive.
7. **Out of scope** — promote-by-digest (SH-022 forge speedup); any workflow YAML changes; renaming native targets.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - EXT `shepherd.contract-adopted` — forge row flips to green in the shepherd fleet-contract-rollout tracker (upstream CAP `dev-cycle.fleet.uniformity`).

## Gherkin acceptance

```gherkin
Scenario: forge exposes all eight contract targets
  Given the forge repo at HEAD
  Then  `make -n test` resolves to real work
  And   `make -n test-affected` resolves to `scripts/smart-check.sh`
  And   `make -n smoke` resolves to real work
  And   `make -n release-artifacts` resolves to real work
  And   `make -n ci-branch` resolves to real work
  And   `make -n ci-patch` resolves to real work
  And   `make -n ci-release` resolves to real work
  And   `make -n ci-nightly` resolves to real work

Scenario: existing forge targets unchanged
  Given the forge repo at HEAD
  Then  `test-fast` recipe is byte-identical to pre-PR
  And   `check` recipe is byte-identical to pre-PR
  And   `check-strict` recipe is byte-identical to pre-PR
```

## Plan doc

[`docs/plan/FG-088-sh019-contract-adoption-plan.md`](../plan/FG-088-sh019-contract-adoption-plan.md).
