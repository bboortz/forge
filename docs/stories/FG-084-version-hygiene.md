---
id: FG-084
slug: version-hygiene
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-084 — Version hygiene: four one-liner contract/ARG/baseline fixes surfaced by full audit

Post-FG-083 full version audit across every surface (`image.yaml tag`, PROMISES `version`, Dockerfile ARGs, upstream pins, CI tool pins, scan-baselines, GH Actions versions) found exactly four actionable items. One real (1), two cosmetic (3, 4), one hygiene (5). Fourth is the biggest by elapsed time (regen requires local scan).

## Scope (one commit, four edits)

### (1) `base/scratch-trixie` tag/PROMISES drift [real]

- `image.yaml tag: "0.2"` vs `PROMISES.yaml version: "0.3"` — two prior promise additions bumped PROMISES but the release tag stayed at 0.2.
- Fix: bump `image.yaml tag:` to `"0.3"`.
- Rollout: next publish of `ghcr.io/bboortz/base/scratch-trixie:0.3` + rev of `:latest` at daily cron.
- Risk: downstream `SCRATCH_BASE_REF=ghcr.io/bboortz/base/scratch-trixie:latest` consumers resolve via `:latest` tag — unaffected. Only operators explicitly pinning `:0.2` would notice a new sibling `:0.3` appearing; none ship that pin publicly.

### (3) `pre-builder/zig-slim-trixie` PROMISES version normalization [cosmetic]

- Current: `version: "0.2.0"` (3-digit, only such image in the fleet)
- Every other image: 2-digit SemVer (`0.1`, `0.2`, etc.)
- Fix: normalize to `"0.2"`.

### (4) `psitransfer-slim-trixie` ARG default [cosmetic]

- Current: `ARG PSITRANSFER_VERSION=latest` with `if [ "${PSITRANSFER_VERSION:-latest}" = "latest" ]; then …` resolver logic
- Every other build-time-resolved version: empty-string default
- Fix: switch to `ARG PSITRANSFER_VERSION=""` and update the `if` check to match empty-string (resolver behaviour unchanged).

### (5) Regenerate 2 stalest scan-baselines [hygiene]

- `base/scratch-trixie/scan-baseline.json`: `2026-11-07` (14 days old)
- `base/python-scratch-trixie/scan-baseline.json`: `2026-11-08` (13 days old)
- These two are called out because they underpin every scratch consumer. The remaining 16 stale baselines (10–13 days each) are not actively lying — zero-CRITICAL images where the daily cron scan regenerates anyway. Deferred to a future FG-085 bulk refresh if ever desired.
- Fix: `make scan-baseline-update IMAGE_DIR=base/scratch-trixie` + `… IMAGE_DIR=base/python-scratch-trixie` + commit the refreshed JSON.

## 9 canonical answers

1. **Who** — Forge maintainer (audit hygiene); future contributor who'd be mis-led by the drift.
2. **When** — Fires post-FG-083 (first comprehensive audit). Convention going forward: FG-083's `verify-promises-version-bump.sh` catches drift of this class automatically.
3. **What success looks like** —
   - `base/scratch-trixie/image.yaml` reads `tag: "0.3"`.
   - `pre-builder/zig-slim-trixie/PROMISES.yaml` reads `version: "0.2"`.
   - `psitransfer-slim-trixie/Dockerfile` default is `""`.
   - Both regen'd scan-baselines show a `generated_at` within the last 24 hours.
   - `make test-fast` green; new FG-084 acceptance red → green.
4. **Urgency** — Quality-of-life; low. Drift is small enough to fit one commit.
5. **Happy path** —
   1. Four edits.
   2. Two `make scan-baseline-update` runs (local scan, ~5 min each).
   3. `make test-fast` green; red acceptance → green.
   4. PR → dev → release → build cron picks up the new tag.
6. **Edge cases / failure modes** —
   - `psitransfer` resolver logic change: the `if` condition must still accept empty string OR the string `latest` for reverse-compat. Keep accepting both.
   - Scan-baseline regen may surface CVEs introduced since 2026-11-07 — if so, decide waive-or-pin at review time. (Expected: zero; scratch images have no dpkg DB.)
   - FG-083's `verify-promises-version-bump` gate: this PR bumps `image.yaml tag:` (not PROMISES promise count), so the gate doesn't fire. `base/scratch-trixie` PROMISES version unchanged.
7. **Out of scope** —
   - (2) from the audit — the leaf-name collision in PROMISES `image:` fields between `pre-builder/*` and `base/*` siblings. Requires 10 file renames + downstream resolver audit. Deferred to a future FG.
   - The 16 other stale scan-baselines (10–12 days).
   - PROMISES `version:` field semantics standardization across the fleet.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_084_version-hygiene.sh`. Four assertions on specific file states.
9. **Capabilities delivered or extended** —
   - EXT `arch.verify-promises-version-bump` (demonstrated catch-up: this FG retroactively satisfies the convention FG-083 just encoded).
   - No new CAPs.

## Gherkin acceptance

```
Scenario: base/scratch-trixie tag matches PROMISES version
  Given FG-084 has shipped
  Then images/base/scratch-trixie/image.yaml tag: equals "0.3"
   And images/base/scratch-trixie/PROMISES.yaml version: equals "0.3"

Scenario: zig-slim-trixie PROMISES normalized
  Given FG-084 has shipped
  Then images/pre-builder/zig-slim-trixie/PROMISES.yaml version: equals "0.2"
   And no PROMISES.yaml uses a 3-digit version string

Scenario: psitransfer ARG empty default
  Given FG-084 has shipped
  Then images/psitransfer-slim-trixie/Dockerfile ARG PSITRANSFER_VERSION default is ""
   And the resolver if-check still triggers resolve path on empty string

Scenario: scratch-trixie + python-scratch baselines refreshed
  Given FG-084 has shipped
  Then images/base/scratch-trixie/scan-baseline.json generated_at is within 24 hours
   And images/base/python-scratch-trixie/scan-baseline.json generated_at is within 24 hours
```

## References

- Audit source: full version sweep after FG-083 ship (`image.yaml`, PROMISES, Dockerfile ARGs, upstream pins, CI tool pins, GH Actions, scan-baselines)
- FG-083 — enforcement gates that catch this class going forward
- Plan: `docs/plan/FG-084-version-hygiene-plan.md`
- Red test: `tests/acceptance/test_FG_084_version-hygiene.sh`
