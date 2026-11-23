---
id: FG-092
slug: check-docs
status: ready
owner: @benni
created: 2026-11-23
---

# FG-092 — Adopt `check-docs` fleet-tier Makefile wrapper

Umbrella is in shepherd: [SH-055 check-docs](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-055-check-docs.md). This FG-092 is the forge-side ledger entry so the per-repo plan-doc + story-doc + CAP conventions stay intact. Forge maps its three doc/metadata-drift gates — `verify-traceability + verify-sid-pins + verify-promises-version-bump` — behind the fleet-canonical `check-docs` tier name. No step renames, no workflow edits. Pure composition.

## 9 canonical answers

1. **Who** — any agent or contributor about to push on forge who wants the same `make check-docs` incantation they'd use on shepherd / healthy / beaconry / HRC / homelab / kernel-test. Also shepherd's forthcoming `--verify-contract` (SH-017) which enforces the canonical tier names fleet-wide.
2. **When** — once per repo, as a Makefile + test + docs PR. No workflow flip needed; the pre-push hook picks up the new `PUSH_STEPS` entry on next run.
3. **What success looks like** — `make check-docs` runs forge's three drift gates (verify-traceability, verify-sid-pins, verify-promises-version-bump); `make -n check-docs` parses cleanly; `.PHONY` declares it; `PUSH_STEPS` + `ci-branch` both include it; CAP registered + bidirectionally linked.
4. **Urgency** — correctness (every doc-staleness incident during the SH-042/044/052/054 push would have been caught pre-push with this gate) + quality-of-life (one command across the fleet) + unblocks fleet-wide `shepherd-bump --verify-contract`.
5. **Happy path** — merge this PR → `make hook-push` now also runs `check-docs` before `check-smart`; `ci-branch` on the next PR runs it too. No change to what runs in nightly CI (check-strict already covers everything via test-fast).
6. **Edge cases** — forge keeps its native delegate names (no renames). `.shepherd.yml` and `.github/workflows/**` are §12-protected and untouched. The three delegates are already in `make test-fast` so false positives on a clean tree would already be observed. hook-push stays inside its ~2 min budget (each delegate is < 2 s on a clean working tree).
7. **Out of scope** — workflow-YAML edits; renaming the underlying step targets; inventing new drift checks (SH-055 explicitly unifies existing entry points, not adds new logic); `mk/ci.mk` include (SH-044); fleet-wide verification (that lives in shepherd SH-055 / SH-017).
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended** (shepherd fleet CAP `dev-cycle.tier.check-docs` registered locally as a one-dot forge id — see CAPABILITIES.md note):
   - NEW `tier.check-docs` — canonical ~15 s doc-drift-tier wrapper mapping to forge's `verify-traceability + verify-sid-pins + verify-promises-version-bump`.
   - EXT `tier.hook-push` — gains `check-docs` as a prerequisite of its `PUSH_STEPS` bundle (CAP entry refreshed in place).

## Gherkin acceptance

```gherkin
Scenario: .PHONY declares check-docs
  Given the forge repo at HEAD
  When  the Makefile .PHONY entries are folded to one logical line
  Then  it declares "check-docs"

Scenario: check-docs dry-run invokes forge's three delegate scripts
  Given the forge repo at HEAD
  When  `make -n check-docs` is parsed
  Then  exit code is 0
  And   the output references scripts/verify-traceability.sh
  And   the output references scripts/verify-sid-pins.sh
  And   the output references scripts/verify-promises-version-bump.sh

Scenario: hook-push dry-run includes check-docs' delegates
  Given the forge repo at HEAD
  When  `make -n hook-push` is parsed
  Then  the output references scripts/verify-traceability.sh

Scenario: PUSH_STEPS + ci-branch both include check-docs
  Given the forge repo at HEAD
  Then  `PUSH_STEPS` in Makefile contains "check-docs"
  And   `ci-branch:` in Makefile contains "check-docs" as a prerequisite

Scenario: CAP registered + bidirectionally linked
  Given the forge repo at HEAD
  Then  docs/specs/CAPABILITIES.md contains "### tier.check-docs"
  And   the entry points back to tests/acceptance/test_FG_092_check-docs.sh
  And   `make verify-traceability` exits 0
```

## References

- Plan: [`docs/plan/FG-092-check-docs-plan.md`](../plan/FG-092-check-docs-plan.md)
- Red test: [`tests/acceptance/test_FG_092_check-docs.sh`](../../tests/acceptance/test_FG_092_check-docs.sh)
- Upstream: [SH-055 (shepherd)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-055-check-docs.md)
- Capabilities: see [`docs/specs/CAPABILITIES.md`](../specs/CAPABILITIES.md)
