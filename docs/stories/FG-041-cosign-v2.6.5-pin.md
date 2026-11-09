---
id: FG-041
slug: cosign-v2.6.5-pin
status: draft
owner: bboortz
created: 2026-11-09
---

# FG-041 — Bump cosign pin v2.4.3 → v2.6.5 (patches HIGH verification-bypass CVE)

Forge has pinned cosign v2.4.3 across all workflows + Makefile since the initial supply-chain setup, with a self-set review deadline of 2026-11-17 (8 days from today). Investigation during the review surfaced:

**v2.4.3 has an unpatched HIGH-severity CVE** — [GHSA-fx35-mq7g-6g98](https://github.com/sigstore/cosign/security/advisories/GHSA-fx35-mq7g-6g98): "Verification bypass via public key in legacy bundle" (published 2026-08-06). Fixed in v2.6.5 (same day). Forge signs every published digest with v2.4.3 — so our own signing path runs a cosign version carrying a verification-bypass bug.

Plus three medium/low CVEs since the v2.4.3 pin was set (verify-blob FP, Rekor-entry accept-any, expired-CA sig validity).

Investigation also updated our model of Sigstore's maintenance posture:
- v2.x is **actively dual-maintained** alongside v3.x — not in a "security-only tail". v2.6.5 shipped Aug 2026; v3.1.4 shipped Oct 2026. Sigstore ships point releases to both lines on coordinated dates.
- v3.1.x reads both v2-format and v3-format signatures — so staying on v2 for signing doesn't block consumers from using v3 CLIs. The v2↔v3 interop story is milder than it looked.

**Decision**: stay on the v2 line (no concrete trigger for v3), but **track the current v2 point release** rather than freezing on v2.4.3. Bump every cosign reference to v2.6.5, update `memory/supply-chain.md` review note, renew the review date (2027-05-17 — 6 months), and add an acceptance test that auto-fails 7 days before the next review date so this drift doesn't slip past unnoticed again.

## 9 canonical answers

1. **Who** — Forge maintainer (me) first; every consumer verifying a Forge-signed image second (they're unaffected because v2 sig format didn't change). Hypothetically every downstream of forge if the v2.4.3 verification-bypass CVE were exploited.

2. **When** — fires at every `cosign sign` call in `build.yml` + every `make sign-local` round-trip. The CVE is in verification logic — most relevant at every `cosign verify` consumer invocation using v2.4.3.

3. **What success looks like**:
   - All five cosign version references pin v2.6.5: `build.yml` × 3 jobs, `nightly.yml`, `Makefile:77`
   - `make sign-local` keeps `--tlog-upload=false` behavior (still works in v2.6.x)
   - `memory/supply-chain.md` ⚠️ note updated: v2.4.3 → v2.6.5, review date 2026-11-17 → 2027-05-17, rationale captured
   - Red acceptance test asserts all pins match, review date is in the future, and fails ≤ 7 days before next review date
   - CI green; no consumer-side changes needed

4. **Urgency** — security. HIGH CVE sits on the signing path for 3 months. Shipping is cheap; delay compounds.

5. **Happy path**:
   1. Merge FG-041 → `dev`.
   2. Promote to `main` via `release.yml`.
   3. Next cron / workflow_dispatch runs install v2.6.5; new signatures created by v2.6.5.
   4. Consumer-side `cosign verify` keeps working (format unchanged; any v2.4.3+ or v3.x client reads it).

6. **Edge cases / failure modes**:
   - **Signature format drift between old :latest and new :latest** — v2.6.5 still signs with the legacy `.sig`-tag format by default (new-bundle-format is opt-in). No format break.
   - **`--tlog-upload=false` removal** — this flag only disappeared in v3; v2.6.x retains it. `make sign-local` unaffected.
   - **A consumer running cosign < v2.4.3** — none known; v2.4.3+ already in the supported range. No action.
   - **Next v2.x security CVE** — the new review date + red test's drift gate (7-day warning) catches the next cycle before it silently expires.

7. **Out of scope**:
   - Upgrading to v3. No current consumer trigger. v3 evaluation stays in IDEAS backlog for the 2027-05-17 review.
   - Auto-bumping v2.x point releases on every release. Manual tracking at review cadence is sufficient — v2 ships ~quarterly, our review is 6-monthly.
   - Changing the keyless-OIDC signing identity. Public contract unchanged.
   - Rewriting `make sign-local` around a tlog-less signing-config. v2.6.x still honors `--tlog-upload=false` directly.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `sign.cosign-keyless-oidc` — unchanged interface, patched implementation.
   - EXT `sign.cosign-local-dev` — unchanged interface, patched implementation.
   - NEW `ci.cosign-pin-drift-gate` — new acceptance test auto-fails 7 days before the review deadline → forces a review decision rather than silent drift.

## Gherkin acceptance

```
Scenario: Every cosign reference across repo pins v2.6.5
  Given every workflow + Makefile reference to cosign version
  Then each one specifies v2.6.5 (no v2.4.3 anywhere; no mixed versions)

Scenario: Supply-chain doc review date is in the future
  Given memory/supply-chain.md's "review due" date
  Then the parsed YYYY-MM-DD is strictly after today

Scenario: Drift gate warns ≤ 7 days before review date
  Given a mocked "today" value within 7 days of the supply-chain.md review date
  When the FG-041 acceptance test runs with that mock
  Then it exits non-zero with a message pointing at supply-chain.md

Scenario: sign-local still works end-to-end
  Given a local cosign v2.6.5 install
  When `make sign-local` runs against forge-local/<image>
  Then cosign signs + pushes without --tlog-upload-related errors
   And `make verify` reads the signature successfully

Scenario: No consumer-side changes required
  Given a consumer running `cosign verify --certificate-identity ... <image>` with any cosign v2.4.3+ or v3.x client
  When they verify a FG-041 freshly-signed image
  Then verification succeeds (signature format unchanged — still legacy .sig tag)
```

## References

- Plan: `docs/plan/FG-041-cosign-v2.6.5-pin-plan.md`
- Red test: `tests/acceptance/test_FG_041_cosign-v2.6.5-pin.sh`
- Trigger: cosign pin review deadline 2026-11-17; investigation 2026-11-09 found [GHSA-fx35-mq7g-6g98](https://github.com/sigstore/cosign/security/advisories/GHSA-fx35-mq7g-6g98) unpatched in v2.4.3
- Related: `memory/supply-chain.md` — pin notice updated by this story
- Future: v3 evaluation deferred to 2027-05-17 review cycle (stored in IDEAS)
