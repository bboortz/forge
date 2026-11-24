---
id: FG-093
slug: verify-index-status
status: in-progress
owner: @benni
created: 2026-11-24
---

# FG-093 — Catch `docs/stories/INDEX.md` ↔ frontmatter status drift

Umbrella is in shepherd: [SH-056 verify-index-status](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-056-verify-index-status.md). This FG-093 is the forge-side ledger entry so the per-repo plan-doc + story-doc + CAP conventions stay intact. Forge adopts the fleet-canonical `scripts/verify-index-status.sh` byte-identical to shepherd's and wires it into `check-docs` as a fourth sibling delegate alongside `verify-traceability`, `verify-sid-pins`, and `verify-promises-version-bump`.

## 9 canonical answers

1. **Who** — any agent or contributor about to push on forge. `verify-traceability` only reads status from frontmatter, so an out-of-sync `INDEX.md` slips through until a human notices. This script closes that specific gap for the whole fleet.
2. **When** — once per repo, as a script + Makefile + test + docs PR. No workflow flip needed; the pre-push hook picks up the new `check-docs` delegate on next run (FG-092 already wired `check-docs` into `PUSH_STEPS` + `ci-branch`).
3. **What success looks like** — `make verify-index-status` passes on a clean tree; `make check-docs` includes it as a fourth sibling delegate; INDEX.md ↔ frontmatter drift blocks pre-push AND CI; CAP registered + bidirectionally linked.
4. **Urgency** — correctness (shepherd PR #55 2026-11-23 shipped 6 shipped-stories whose INDEX rows still said `draft`/`in-progress`; forge's own INDEX had 50+ status mismatches + 8 missing rows when this script was first run — all caught + fixed as part of this PR) + unblocks future fleet-wide `shepherd-bump --verify-contract` symmetry.
5. **Happy path** — merge this PR → `make hook-push` now also runs `verify-index-status` before `check-smart`; `ci-branch` on the next PR runs it too. INDEX drift fails fast with a line per mismatch.
6. **Edge cases** — script skips `INDEX.md` itself + `_*.md` templates; missing INDEX.md exits 0 with a one-line note (nothing to check); missing row for a shipped+ story fails loud; status-column parsing splits on `|` and trims whitespace. Fleet-canonical INDEX column order is `ID | Status | Slug | One-liner` — forge's prior `ID | Slug | Status | One-liner` was reordered as part of this PR's drift-sync (invisible to human readers; makes the grep-friendly promise honest).
7. **Out of scope** — workflow-YAML edits; renaming or deepening the script (it stays byte-identical to shepherd's across the fleet); adding new drift checks (SH-056 scope is tight); fleet-wide verification (that lives in shepherd SH-017).
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended** (shepherd fleet CAP `dev-cycle.verify-index-status` registered locally as a one-dot forge id — see CAPABILITIES.md note):
   - NEW `tier.verify-index-status` — INDEX.md ↔ frontmatter status drift gate; byte-identical script across the fleet.
   - EXT `tier.check-docs` — gains `verify-index-status` as a fourth sibling delegate (CAP entry refreshed in place).

## Gherkin acceptance

```gherkin
Scenario: verify-index-status script is byte-identical to shepherd's
  Given the forge repo at HEAD
  Then  scripts/verify-index-status.sh matches shepherd's scripts/verify-index-status.sh byte-for-byte

Scenario: .PHONY declares verify-index-status
  Given the forge repo at HEAD
  When  the Makefile .PHONY entries are folded to one logical line
  Then  it declares "verify-index-status"

Scenario: verify-index-status target exists and dry-runs cleanly
  Given the forge repo at HEAD
  When  `make -n verify-index-status` is parsed
  Then  exit code is 0
  And   the output references scripts/verify-index-status.sh

Scenario: check-docs includes verify-index-status as a fourth sibling delegate
  Given the forge repo at HEAD
  Then  `check-docs:` in Makefile includes "verify-index-status" as a prerequisite
  And   `make -n check-docs` output references scripts/verify-index-status.sh

Scenario: verify-index-status passes on the current tree
  Given the forge repo at HEAD
  When  `./scripts/verify-index-status.sh` runs
  Then  exit code is 0

Scenario: CAP registered + bidirectionally linked
  Given the forge repo at HEAD
  Then  docs/specs/CAPABILITIES.md contains "### tier.verify-index-status"
  And   the entry points back to tests/acceptance/test_FG_093_verify-index-status.sh
  And   `make verify-traceability` exits 0
```

## References

- Plan: [`docs/plan/FG-093-verify-index-status-plan.md`](../plan/FG-093-verify-index-status-plan.md)
- Red test: [`tests/acceptance/test_FG_093_verify-index-status.sh`](../../tests/acceptance/test_FG_093_verify-index-status.sh)
- Upstream: [SH-056 (shepherd)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-056-verify-index-status.md)
- Capabilities: see [`docs/specs/CAPABILITIES.md`](../specs/CAPABILITIES.md)