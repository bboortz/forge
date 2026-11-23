---
id: FG-091
slug: hook-tiers
status: ready
owner: @benni
created: 2026-11-23
---

# FG-091 — Adopt `hook-commit` + `hook-push` fleet tiers

Umbrella is in shepherd: [SH-042 hook tiers](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-042-hook-tiers.md). This FG-091 is the forge-side ledger entry so the per-repo plan-doc + story-doc + CAP conventions stay intact. Forge maps its native steps — `lint + verify-sid-pins + verify-traceability` for commit; `check-smart` for push — behind the fleet-canonical tier names. No step renames, no workflow edits.

## 9 canonical answers

1. **Who** — any agent or contributor about to commit / push on forge who wants the same `make hook-commit` / `make hook-push` incantation they'd use on shepherd / healthy / beaconry / HRC / homelab / kernel-test. Also shepherd's forthcoming `--verify-contract` (SH-017) which will enforce the canonical tier names from SH-044 onward.
2. **When** — once per repo, as a Makefile+test+docs PR. No repo-settings or workflow flip needed.
3. **What success looks like** — `make hook-commit` runs forge's commit bundle (~15 s budget); `make hook-push` runs forge's push bundle (~2 min budget); `make -n` of either parses cleanly; `.PHONY` declares both; CAPs registered + bidirectionally linked.
4. **Urgency** — correctness (fleet tier-name uniformity unblocks SH-017 verifier) + quality-of-life (one command instead of seven dialects).
5. **Happy path** — merge this PR → `make hook-commit` chains lint + verify-sid-pins + verify-traceability; `make hook-push` runs check-smart. No change to what runs in CI (ci-branch / ci-nightly still call their existing targets).
6. **Edge cases** — forge keeps its native step names (`lint`, `verify-sid-pins`, `verify-traceability`, `check-smart`) — no renames. `.shepherd.yml` and `.github/workflows/**` are §12-protected and untouched. `check-smart` already honours FG-017 scoping so hook-push stays fast on narrow diffs.
7. **Out of scope** — workflow-YAML edits; renaming the underlying step targets; `mk/ci.mk` include (SH-044); fleet-wide verification (that lives in shepherd SH-044 / SH-017).
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended** (shepherd fleet CAPs `dev-cycle.tier.hook-commit` + `dev-cycle.tier.hook-push` registered locally as one-dot forge ids — see CAPABILITIES.md note):
   - NEW `tier.hook-commit` — canonical ~15 s commit-tier wrapper mapping to forge's `lint + verify-sid-pins + verify-traceability`.
   - NEW `tier.hook-push` — canonical ~2 min push-tier wrapper mapping to forge's `check-smart`.

## Gherkin acceptance

```gherkin
Scenario: .PHONY declares hook-commit and hook-push
  Given the forge repo at HEAD
  When  the Makefile .PHONY entries are folded to one logical line
  Then  it declares both "hook-commit" and "hook-push"

Scenario: hook-commit dry-run invokes forge's commit steps
  Given the forge repo at HEAD
  When  `make -n hook-commit` is parsed
  Then  exit code is 0
  And   the output references hadolint (from lint)
  And   the output references scripts/verify-sid-pins.sh
  And   the output references scripts/verify-traceability.sh

Scenario: hook-push dry-run invokes check-smart
  Given the forge repo at HEAD
  When  `make -n hook-push` is parsed
  Then  exit code is 0
  And   the output references scripts/smart-check.sh

Scenario: CAPs registered + bidirectionally linked
  Given the forge repo at HEAD
  Then  docs/specs/CAPABILITIES.md contains "### tier.hook-commit"
  And   docs/specs/CAPABILITIES.md contains "### tier.hook-push"
  And   both entries point back to tests/acceptance/test_FG_091_hook-tiers.sh
  And   `make verify-traceability` exits 0
```

## References

- Plan: [`docs/plan/FG-091-hook-tiers-plan.md`](../plan/FG-091-hook-tiers-plan.md)
- Red test: [`tests/acceptance/test_FG_091_hook-tiers.sh`](../../tests/acceptance/test_FG_091_hook-tiers.sh)
- Upstream: [SH-042 (shepherd)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-042-hook-tiers.md)
- Capabilities: see [`docs/specs/CAPABILITIES.md`](../specs/CAPABILITIES.md)
