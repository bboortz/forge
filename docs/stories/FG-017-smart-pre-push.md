---
id: FG-017
slug: smart-pre-push
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-017 — Smart pre-push: scope-aware check-strict, no lint divergence

Cut local pre-push from ~15 min (full cold-cache `check-strict`) to ~2-3 min typical, without weakening verification. Lessons stolen from `bb-claw/homelab`'s `scripts/smart-deploy.sh` + `scripts/test-updates.sh`; hardened against the "CI fails lint after local passes" class of bug that bites homelab today.

### Three parts

- **A — Affected-image scope**: `scripts/smart-check.sh` reads `git diff $BASE..HEAD`, derives the set of touched images + their EXPECTATIONS fan-out (reusing the FG-010 contracts graph as the single source of truth — no hand-maintained path manifest like homelab's). Builds + smokes + acceptance-tests only the affected set. Bailout triggers:
  - `scripts/*`, `Makefile`, `.pre-commit-config.yaml`, `.github/workflows/*` touched → full
  - `images/scratch-base-trixie/*` touched → full (every scratch derivative affected)
  - `>4` images in scope → full (conservative cap, matches homelab's >5-role bailout)
  - Any changed `PROMISES.yaml` with a removed/modified promise → fan-out to every dependent via `verify-contracts.py`
- **B — Dedup acceptance smokes under `make check`**: `make check` exports `_FORGE_IN_CHECK=1`. Each `tests/acceptance/test_FG_*.sh` wraps its `scripts/test-images.sh <name>` section in an `if ... then` guarded by that env. Standalone invocation (`bash tests/acceptance/test_FG_010...sh`) stays unchanged — full run including smokes.
- **C — Unscoped-lint hardening**: lint runs on the **full** git-tracked file set (`git ls-files`) in pre-push AND CI via the same `make test-fast` target. No scoping, no diff heuristic. Adds an exec-bit check so a new `.sh` without `chmod +x` fails loudly instead of being silently skipped by shellcheck. Directly addresses homelab's "pre-push passed, CI failed lint" pain.

### Stamp-based rebuild skip — deferred

See `docs/plan/IDEAS.md § Stamp-based rebuild skip`. Optional Part D if real-world post-FG-017 numbers show most pushes still spend >1 min in docker-build. Not shipped here because invalidation rules (EXPECTATIONS fan-out, upstream SHA for externally-sourced images) deserve their own think-through.

## 9 canonical answers

1. **Who** — Forge maintainers running `git push` on a feature branch; GHA PR CI (optionally).
2. **When** — on every pre-push; CI PR may opt in later (tracked separately).
3. **Success looks like** —
   - `make check-smart` runs test-fast + scoped build/smokes/acceptance against the affected image set.
   - Docs-only change: ~15 sec. 1 image: ~2-3 min. 3 images: ~5-6 min. >4 images or structural change: bailout to full `check-strict` (~15 min).
   - `make test-fast` always runs full-repo lint; both locally and in CI. No chance of divergence.
   - All 17 existing acceptance tests pass unchanged (Part B's env is additive).
   - A new FG-017 acceptance test proves every scope decision + the dedup behavior.
   - Nightly GHA cron continues running full `make check-strict` on `dev` HEAD — safety net for "smart gate was wrong about the affected set".
4. **Urgency** — quality-of-life for devs; unblocks faster iteration cycles. Medium.
5. **Happy path** — see Design delta in the plan doc. Summary: one new script + one env var + one lint input change.
6. **Edge cases / failure modes** —
   - Changes to Forge's own scripts (verifier, build-image.sh, etc.) → full run bailout (correct — the gate itself could be broken).
   - Changes to `scratch-base-trixie/` → full run bailout.
   - Dev edits `images/X/PROMISES.yaml` adding a promise → only X is affected (no dependent fan-out).
   - Dev edits `images/X/PROMISES.yaml` removing/modifying a promise → EVERY dependent fans in via `verify-contracts`.
   - Docs-only (`*.md`, `docs/*`) → test-fast only.
   - Externally-sourced image's upstream SHA advances between runs (same local diff, upstream moved) → smart gate ignores this at pre-push time; daily cron catches it. Documented in the smart-check.sh header.
7. **Out of scope** —
   - Part D (stamp cache) — see IDEAS.
   - CI matrix parallelism (FG-018).
   - Switching CI PR gate from full-check to smart-check (separate story; FG-017 keeps CI full).
8. **How we know it's done** — FG-017 acceptance test green + `make check-strict` green (still works end-to-end) + pre-push hook updated to smart variant.
9. **Capabilities**:
   - NEW `tooling.smart-check` — scope-aware pre-push gate
   - NEW `tooling.unscoped-lint` — lint over git-tracked set, exec-bit check, single target for pre-push + CI
   - EXT `test.image-smoke-suite` — acceptance tests gain `_FORGE_IN_CHECK` dedup guard

## Gherkin acceptance

```
Scenario: docs-only change
  Given only docs/stories/*.md files changed
  When `make check-smart` runs
  Then only test-fast is executed (lint + verify-*)
   And no docker builds are triggered
   And exits 0

Scenario: single-image change
  Given only images/beaconry-scout/* files changed (direct, no fan-out)
  When `make check-smart` runs
  Then test-fast runs
   And exactly beaconry-scout is built + smoked + its acceptance test run
   And no other images are built
   And exits 0

Scenario: scratch-base-trixie change triggers full bailout
  Given images/scratch-base-trixie/* files changed
  When `make check-smart` runs
  Then it logs "full-run bailout" with reason "scratch-base-trixie touched"
   And delegates to `make check-strict`

Scenario: scripts/ change triggers full bailout
  Given scripts/build-image.sh changed
  When `make check-smart` runs
  Then it logs "full-run bailout" with reason "tooling touched"

Scenario: >4 images triggers full bailout
  Given 5 image dirs touched
  When `make check-smart` runs
  Then bailout fires with reason "image count > 4"

Scenario: PROMISES.yaml promise removed cascades
  Given images/python-scratch-trixie/PROMISES.yaml had a promise removed
  When `make check-smart` runs
  Then scope includes python-scratch-trixie + every dependent (scout, hub, ham-agent, …)

Scenario: unscoped-lint catches an unrelated file
  Given shellcheck would fail on an untouched scripts/*.sh file
  When `make check-smart` runs
  Then test-fast fails before any build runs

Scenario: exec-bit check catches a non-executable .sh
  Given a new tests/acceptance/test_FG_*.sh exists without +x
  When `make check-smart` runs
  Then make test-fast fails with "missing exec bit"

Scenario: standalone acceptance test keeps full behavior
  Given bash tests/acceptance/test_FG_010_image-contracts.sh (no env)
  When it runs
  Then it includes its internal `scripts/test-images.sh` invocation
   And exits 0

Scenario: same test under make check skips the duplicate smoke run
  Given _FORGE_IN_CHECK=1 bash tests/acceptance/test_FG_010_image-contracts.sh
  When it runs
  Then the internal test-images.sh call is skipped
   And the rest of the test still runs
```

## References

- Plan: [`docs/plan/FG-017-smart-pre-push-plan.md`](../plan/FG-017-smart-pre-push-plan.md)
- Red test: [`tests/acceptance/test_FG_017_smart-pre-push.sh`](../../tests/acceptance/test_FG_017_smart-pre-push.sh)
- Deferred follow-up: `docs/plan/IDEAS.md § Stamp-based rebuild skip`
- Prior art: `bb-claw/homelab/scripts/smart-deploy.sh` + `scripts/test-updates.sh`
