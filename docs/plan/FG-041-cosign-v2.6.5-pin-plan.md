# FG-041 — Plan: cosign v2.4.3 → v2.6.5 pin bump

**Story**: [`docs/stories/FG-041-cosign-v2.6.5-pin.md`](../stories/FG-041-cosign-v2.6.5-pin.md)
**Status**: shipped
**Branch**: `feat/FG-041-cosign-v2.6.5-pin`

## Design delta

### Version pin updates (5 references across 3 files)

```
.github/workflows/build.yml   line 68  comment "v2.4.3 pinned — review by 2026-11-17"  → "v2.6.5 pinned — review by 2027-05-17"
                              line 74  comment "v2.4.3 pinned"                         → "v2.6.5 pinned"
                              line 75  cosign:v2.4.3                                    → cosign:v2.6.5
                              line 168 comment duplicate (same job pattern)             → same
                              line 174 same
                              line 175 cosign:v2.4.3                                    → cosign:v2.6.5
                              line 270 same
                              line 276 same
                              line 277 cosign:v2.4.3                                    → cosign:v2.6.5
.github/workflows/nightly.yml line 61  cosign:v2.4.3                                    → cosign:v2.6.5
Makefile                      line 77  cosign/releases/download/v2.4.3/                 → v2.6.5/
```

### `memory/supply-chain.md` header note

```diff
-**⚠️ Cosign pin — review due 2026-11-17.** Both CI (`build.yml`) and local (`make sign-local` / `make verify`) are pinned to cosign **v2.4.3**. v3.x stores signatures as OCI 1.1 referrers (no `.sig` tag) and dropped `--tlog-upload=false`, which would break both consumer-side verify with v2 clients and the local sign-local round-trip. Review path: upgrade everything to v3 + rewrite sign-local around a tlog-less signing-config, or renew the v2 pin.
+**⚠️ Cosign pin — review due 2027-05-17.** Both CI (`build.yml`) and local (`make sign-local` / `make verify`) are pinned to cosign **v2.6.5** (bumped from v2.4.3 by FG-041 to patch GHSA-fx35-mq7g-6g98, a HIGH verification-bypass CVE fixed in v2.6.5). v2.x is actively dual-maintained alongside v3.x — pinning to v2.x latest keeps us in-security with no consumer-side CLI change needed. v3 migration deferred: no concrete trigger (no consumer ask, no v3-only feature we need). v3.1.x reads both v2 and v3 signature formats, so any consumer can verify. Re-evaluate on review date OR immediately if: Sigstore announces v2 EOL, a consumer explicitly asks for v3-format sigs, or a HIGH/CRITICAL CVE lands on the pinned v2.x and fix is v3-only.
```

### Red acceptance test — `tests/acceptance/test_FG_041_cosign-v2.6.5-pin.sh`

4 sections:

1. **Pin consistency** — glob every `.github/workflows/*.yml` + `Makefile` + `scripts/*.sh`; extract every reference to `cosign:vX.Y.Z` or `cosign-linux-amd64` download URL; assert all cite the same version AND that version is `v2.6.5`.

2. **Review date is in the future** — parse `memory/supply-chain.md`'s "review due YYYY-MM-DD" string; assert the date is strictly after today. Using `date -d` for arithmetic.

3. **Drift gate (the whole point of this check being in CI)** — assert the review date is **more than 7 days in the future**. If it's within 7 days, FAIL with a message telling the operator to decide (renew / upgrade / choose) and ship a decision before the deadline hits.

4. **Consistent pin ↔ doc** — grep `memory/supply-chain.md` for `v2.6.5` to confirm the doc's version string matches the actual pin. Guards against the review-date being updated while forgetting the version string (or vice versa).

Script will use `FG_041_TODAY=YYYY-MM-DD` env var for the drift-gate assertion to be testable (tests can set it to simulate "7 days before review" and confirm the test fails there).

### `docs/CAPABILITIES.md`

NEW `ci.cosign-pin-drift-gate` entry:

> The FG-041 acceptance test fails the build 7 days before the cosign pin review date declared in `memory/supply-chain.md`. Prevents silent drift past self-set review deadlines. On trigger: operator decides to renew the pin, upgrade the pin, or migrate to v3 — then ships the decision.

EXT notes on `sign.cosign-keyless-oidc` + `sign.cosign-local-dev`: "FG-041 bumped pin to v2.6.5 to patch GHSA-fx35-mq7g-6g98."

## Alternatives rejected

- **Renew v2.4.3 pin without bumping** — rejected because v2.4.3 has an unpatched HIGH CVE (GHSA-fx35-mq7g-6g98). The original "renew" recommendation was based on incomplete information (I hadn't checked the v2.x release cadence or open advisories). Investigation surfaced active v2 maintenance + 4 CVEs since v2.4.3.
- **Upgrade to v3.1.4** — no concrete trigger. v3-format sigs would be readable by v3 CLIs but require consumer CLI upgrades. Deferred to next review cycle (2027-05-17) with the understanding that v3 is a clean option when triggered.
- **Auto-bump v2 point releases** — e.g. a daily `gh api` call that checks for new v2.x releases and opens a PR. Too much automation for a rarely-moving pin; 6-monthly review cadence suffices. If desired later, can add.
- **Track v2.6.4 (previous point)** — v2.6.5 is the version carrying the HIGH CVE fix. v2.6.4 is still vulnerable.
- **Custom tlog-less signing-config for v3** — unnecessary while on v2; `--tlog-upload=false` still works directly.

## Breaking changes

None.
- Signature format unchanged (v2 legacy `.sig` tag — any v2.4.3+ or v3.x client verifies).
- Verify command in README unchanged.
- Consumer CLI versions unaffected.
- `make sign-local` behavior identical (`--tlog-upload=false` still works in v2.6.x).

## Merge plan

- Red acceptance test green post-fix.
- `make test-fast` + pre-push `check-smart-strict` green.
- No image rebuild required — this is a CI-pipeline-tooling change, not an image change.

## Rollout plan

1. Land FG-041 on `dev` via PR.
2. Promote to `main` via `release.yml` dispatch.
3. Next `build.yml` cron (or on-demand dispatch) uses v2.6.5 cosign to sign all published digests.
4. Operators pulling new digests after that cron get images signed by the patched cosign.
5. No action required from consumers — their verify commands unchanged.
6. Red test prevents the next drift: 2027-05-10 (7 days before next review date 2027-05-17) CI will start failing until operator ships a decision.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: every cosign reference pins v2.6.5 | `tests/acceptance/test_FG_041_...sh` § 1 | ⏳ |
| Scenario: review date in the future | § 2 | ⏳ |
| Scenario: drift gate warns ≤ 7 days | § 3 | ⏳ |
| Scenario: sign-local still works | smoke_sign_local_v265.sh (optional, deferred) | ⏳ |
| Scenario: no consumer-side changes | documented; no consumer touches | ⏳ |
| NEW CAP `ci.cosign-pin-drift-gate` | `docs/CAPABILITIES.md` + acceptance § 3 | ⏳ |
| EXT `sign.cosign-keyless-oidc` + `sign.cosign-local-dev` | `docs/CAPABILITIES.md` + supply-chain.md | ⏳ |
