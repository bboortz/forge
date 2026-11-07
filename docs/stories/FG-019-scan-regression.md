---
id: FG-019
slug: scan-regression
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-019 — Scan-regression gate: PR fails on new CRITICAL CVE vs in-repo baseline

Today Forge **attaches** grype scans as attestations but never **gates** on them. A PR can introduce a new CRITICAL CVE (via sid-pin change, Dockerfile tweak, derivative addition, or a dep bump in an externally-sourced image) and nothing stops the merge until a human eyeballs the next scan. FG-019 closes the hole.

### Design decisions (resolved)

| Q | Decision | Why |
|---|---|---|
| Severity threshold | **CRITICAL only** | Highest signal; HIGH-tier findings often have exploitability caveats not worth PR-blocking |
| Baseline source | **`images/<name>/scan-baseline.json`** (committed, per-image) | Diffs what the PR itself changes; CVE-DB drift surfaces via nightly cron, not random PRs |
| Waiver mechanism | **Extends FG-010 PROMISES** — `absence.os-cves.waivers: [{cve, reason, until}]` | Reuses semver gate, verify-contracts validation, expiry check |
| New-image behavior | **Auto-baseline** on first build if `scan-baseline.json` is absent | Zero manual bootstrap; subsequent runs gate normally |

### Shape

- `scripts/scan-regression.py` — per-image grype diff logic. Inputs: image name + current baseline file. Runs grype on local build, filters to `Critical`, subtracts waivered CVE IDs (from PROMISES.yaml), subtracts baseline CRITICALS. Any residual → fail.
- `images/<name>/scan-baseline.json` — committed JSON (one file per image). Shape: `{"version": 1, "critical_cves": ["CVE-XXXX-YYYY", ...], "generated_at": "..."}`. Minimal — not the full grype output, just the CVE IDs at CRITICAL severity.
- `make scan-baseline-update IMAGE_DIR=<name>` — manual target that regenerates the baseline from the current local build. Devs run it only when intentionally accepting a baseline change (e.g., accepting a new CRITICAL because upstream can't patch).
- `make scan-regression` — new gate target. Runs per affected image (FG-017 scope). Added into `make check` + smart-check's per-image loop.
- `scripts/verify-contracts.py` — extended: validate `absence.os-cves.waivers` schema (each has `cve`, `reason`, `until` as date); flag expired waivers as errors.
- 8 baseline files pre-generated in this PR — zero-CRITICAL state for all existing images (per earlier smokes: all 8 report zero Debian-source matches; if there are PyPI CRITICAL findings, baseline them explicitly).

### Integration with FG-017

Scan-regression runs **per affected image in smart-check's scoped loop**. No "scan everything on every PR" overhead — a 1-image PR scans exactly 1 image (~10s grype + ~1s diff). Smart-check already builds the image; scan-regression consumes the just-built artifact.

## 9 canonical answers

1. **Who** — any PR that touches an image (direct or via FG-010 EXPECTATIONS fan-out). Caught by CI + pre-push.
2. **When** — every PR / pre-push / nightly / daily cron.
3. **Success looks like** —
   - 8 `scan-baseline.json` files committed; each carries the current zero-CRITICAL state of its image.
   - `make scan-regression` builds + scans an image and diffs vs its baseline.
   - Synthetic test: an injected fake CRITICAL finding → gate fails with the CVE id named.
   - Waiver flow: add a CRITICAL to a baseline via `make scan-baseline-update`, OR add to `absence.os-cves.waivers` with reason + until → gate passes; verify-contracts validates the waiver.
   - `verify-contracts.py` fails with expired waivers.
   - Integrated into smart-check per-image loop (no separate full-repo scan phase).
4. **Urgency** — security/product tier. Closes the real CVE-regression hole.
5. **Happy path** —
   1. `scripts/scan-regression.py` (new): grype run + CRITICAL filter + waiver subtraction + baseline diff.
   2. `images/<name>/scan-baseline.json` for each of the 8 current images.
   3. PROMISES.yaml `absence.os-cves` promises gain optional `waivers: [{cve, reason, until}]`.
   4. `scripts/verify-contracts.py` extended: validate waiver fields + check `until` date hasn't passed (expired waivers = error).
   5. `scripts/smart-check.sh`: insert `scan-regression` call after `test-images.sh <image>` in the per-affected-image loop.
   6. `Makefile`: `scan-regression` + `scan-baseline-update` targets.
   7. `.github/workflows/nightly.yml`: no change — nightly already runs check-strict which includes make check → scan-regression.
   8. FG-019 acceptance test.
6. **Edge cases / failure modes** —
   - Baseline file missing → auto-bootstrap (write current scan as new baseline), warn. Dev must explicitly commit it.
   - grype DB unreachable → gate errors cleanly (distinct exit code) rather than passing silently.
   - Image doesn't have `absence.os-cves` promise (e.g. telegram-mock, intentionally OS-CVE-permissive) → no scan-regression check runs for that image. Document the opt-out.
   - Externally-sourced image at `ref: latest` with upstream advance introducing CRITICAL → the PR's diff shows 0 changes to beaconry files, so smart-check skips it → nightly catches it the next morning. Documented tradeoff.
   - Waiver's `until` passes mid-PR — expired waiver = verify-contracts fails = PR blocked. Forces renewal or upstream fix.
7. **Out of scope** —
   - HIGH-severity gating (Q1 decision locked to CRITICAL only).
   - Diff vs published `:latest` attestation (Q2 locked to in-repo baseline).
   - Auto-opening PRs for waiver renewals (future).
   - SBOM-regression gate (separate story if needed).
8. **How we know it's done** — FG-019 acceptance (6 scenarios) green + `make check-strict` green across all 8 images + the 8 baselines committed.
9. **Capabilities**:
   - NEW `scan.regression-gate` — PR fails on new CRITICAL vs committed baseline
   - NEW `scan.cve-waivers` — waivers via PROMISES.yaml with reason + expiry
   - EXT `tooling.smart-check` — integrates scan-regression in the per-image loop
   - EXT `image.zero-os-cves` — "zero" now means "zero unwaivered CRITICAL in baseline"

## Gherkin acceptance

```
Scenario: baseline-equal scan passes
  Given images/<img>/scan-baseline.json lists CRITICALs = [CVE-A]
   And current grype scan reports CRITICALs = [CVE-A]
  When make scan-regression IMAGE_DIR=<img>
  Then it exits 0

Scenario: new CRITICAL fails
  Given baseline lists CRITICALs = []
   And current grype scan finds a new CRITICAL CVE-X
  When make scan-regression IMAGE_DIR=<img>
  Then it exits 1 with "new CRITICAL CVE-X not in baseline and not waivered"

Scenario: waivered CRITICAL passes
  Given PROMISES.yaml absence.os-cves.waivers includes {cve: CVE-X, reason: "...", until: 2027-01-01}
   And current grype scan finds CRITICAL CVE-X (not in baseline)
  When make scan-regression IMAGE_DIR=<img>
  Then it exits 0

Scenario: expired waiver is rejected
  Given PROMISES.yaml waiver {cve: CVE-X, until: 2024-01-01}  # already past
  When make verify-contracts
  Then it exits 1 with "waiver for CVE-X expired on 2024-01-01"

Scenario: missing baseline auto-bootstraps
  Given a brand-new image with no scan-baseline.json
  When make scan-regression IMAGE_DIR=<new-img>
  Then the current scan is written to images/<new-img>/scan-baseline.json
   And it exits 0 with a warning to commit the baseline

Scenario: scan-regression runs in smart-check per-image loop
  Given a PR touches images/beaconry-scout/
  When CI runs make check-smart
  Then scan-regression runs for beaconry-scout only
   And no other images are scanned
```

## References

- Plan: [`docs/plan/FG-019-scan-regression-plan.md`](../plan/FG-019-scan-regression-plan.md)
- Red test: [`tests/acceptance/test_FG_019_scan-regression.sh`](../../tests/acceptance/test_FG_019_scan-regression.sh)
- Depends on: FG-017 (smart-check scope), FG-010 (PROMISES waivers mechanism)
