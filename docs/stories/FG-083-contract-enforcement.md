---
id: FG-083
slug: contract-enforcement
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-083 — Contract enforcement: no orphan smokes, CAP-has-promise, promise-add bumps PROMISES version

Three mechanical gates that would have prevented FG-082's cleanup entirely. All three enforce an existing convention that was previously only "maintainer discipline".

## Scope — three new invariants

### (a) No orphan smoke tests

**Rule**: every `images/<x>/tests/smoke_*.sh` must be referenced by at least one `tests:` entry in some `PROMISES.yaml`.

**Why**: FG-082 found 4 smokes running in CI with no contract line. Tests must map to promises per DD-TGD; the inverse wasn't enforced.

**Shape**: `scripts/verify-no-orphan-smokes.py` — walks every smoke path, parses every PROMISES.yaml, fails on orphans. Explicit allowlist (`_ORPHAN_SMOKES_ALLOWLIST`) escape hatch; expected to stay empty.

### (b) CAP-has-promise (bidirectional traceability)

**Rule**: every CAP id in `docs/CAPABILITIES.md` must be named by at least one `caps:` entry in some `PROMISES.yaml`.

**Why**: `verify-traceability.sh` currently enforces CAP→test (every CAP has a "Covered by:" pointer) and test→CAP (every acceptance test names valid CAPs). It does NOT enforce CAP→PROMISES, which would catch a CAP that was documented in CAPABILITIES but not actually promised by any image. Closes the last bidirectional gap.

**Shape**: extend `scripts/verify-traceability.sh` with a new Rule 4.

### (c) Adding a promise bumps the PROMISES `version:`

**Rule**: if a `PROMISES.yaml` gains or loses a promise `- id:` line between base branch and HEAD, its `version:` field must also change.

**Why**: prior FGs that added promises bumped `version:` by minor; FG-082 missed the bump across 3 files and nothing caught it. Convention is now a rule.

**Shape**: `scripts/verify-promises-version-bump.sh` — git-diff aware; default base is `origin/dev` (overridable via `GIT_DIFF_BASE` env). On PR CI, resolves base from `GITHUB_BASE_REF`. Local pre-commit skips silently if no git diff is resolvable (e.g. clean clone outside a branch context).

## 9 canonical answers

1. **Who** — Forge maintainer. Future contributor who'd otherwise learn the convention only after a code-review round-trip.
2. **When** — Fires at `make test-fast`, pre-commit, and PR CI. Blocks a commit that would otherwise regress the three invariants.
3. **What success looks like** —
   - `scripts/verify-no-orphan-smokes.py` exits 0 on current tree (zero orphans post-FG-082).
   - `verify-traceability.sh` grows Rule 4; still exits 0 on current tree.
   - `verify-promises-version-bump.sh` exits 0 on this very branch (the branch's own PROMISES diff is a no-op).
   - All three wired into `make test-fast`.
4. **Urgency** — Quality-of-life; low urgency on its own but eliminates a whole class of post-ship cleanup (FG-082 was the second such sweep).
5. **Happy path** —
   1. Three scripts land; `make test-fast` grows 3 `✓` lines.
   2. Local `make check-strict` / pre-commit already run `test-fast`, so pre-commit coverage is automatic.
   3. PR CI picks it up via existing `make test-fast` invocation.
6. **Edge cases / failure modes** —
   - **(a) orphan intentionally present** — allowlist. Single list in `verify-no-orphan-smokes.py`. Any addition should reference a story ID.
   - **(b) CAP legitimately without PROMISES** — e.g. a CAP about an acceptance-test-only shape (`test.smoke-server-helper`, `build.two-stage-scratch`). These are meta-CAPs. Allowlist them (`_CAPS_WITHOUT_PROMISES_ALLOWLIST`).
   - **(c) rebase / promise-reordering** — git diff detects line additions even on pure reorders. Script matches `^  - id:` lines, sorted, so reorders don't fire.
   - **(c) no git context locally** — if `git merge-base` fails (shallow clone, detached HEAD, no base branch), skip with `⚠` instead of fail. PR CI always has context.
7. **Out of scope** —
   - "Every PROMISES.yaml schema-version alignment with image.yaml tag:" — already audited as intentionally decoupled (contract-schema version ≠ release version).
   - "Prose drift" (dumb-init-style stale comments) — not mechanically detectable.
   - New CAPs or PROMISES additions.
   - Behaviour changes to any image.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_083_contract-enforcement.sh`. All 3 scripts exit 0 on `make test-fast`; red artificial scenarios (introduce an orphan, drop a promise without version bump, orphan a CAP) each cause the respective gate to fail.
9. **Capabilities delivered or extended** —
   - NEW `arch.verify-no-orphan-smokes` — every smoke script has a PROMISES home.
   - NEW `arch.verify-cap-has-promise` — every CAP is promised by ≥1 image (modulo meta-CAP allowlist).
   - NEW `arch.verify-promises-version-bump` — changing promise count mandates version bump.

## Gherkin acceptance

```
Scenario: current tree is clean under all three gates
  Given FG-083 has shipped
  When I run bash scripts/verify-no-orphan-smokes.py
   And I run bash scripts/verify-traceability.sh
   And I run bash scripts/verify-promises-version-bump.sh
  Then all three exit 0

Scenario: introducing an orphan smoke fails (a)
  Given FG-083 has shipped
  When I create images/<existing>/tests/smoke_orphan.sh that no PROMISES references
  Then bash scripts/verify-no-orphan-smokes.py exits non-zero
   And the error names the orphan path

Scenario: CAP with zero promise coverage fails (b)
  Given FG-083 has shipped
  When I add a CAP to CAPABILITIES.md that no PROMISES caps: entry mentions
  Then bash scripts/verify-traceability.sh exits non-zero
   And the error names the orphan CAP

Scenario: adding a promise without version bump fails (c)
  Given FG-083 has shipped
   And the current branch adds a promise to some PROMISES.yaml
  When I run bash scripts/verify-promises-version-bump.sh with base=origin/dev
  Then exit is non-zero
   And the error names the PROMISES.yaml that needs a version bump
```

## References

- Plan: `docs/plan/FG-083-contract-enforcement-plan.md`
- Red test: `tests/acceptance/test_FG_083_contract-enforcement.sh`
- Precedent: FG-064 (verify-dockerfile-conformance.py), FG-068 (verify-source-inventory.py) — same shape, different invariant.
- Trigger: FG-082 contract cleanup surfaced that 4 orphan smokes + 3 missing version bumps slipped through.
