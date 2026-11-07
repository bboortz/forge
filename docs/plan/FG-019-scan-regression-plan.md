# FG-019 — Plan: scan-regression gate

**Story**: [`docs/stories/FG-019-scan-regression.md`](../stories/FG-019-scan-regression.md)
**Status**: in-progress
**Branch**: `feat/FG-019-scan-regression`

## Design delta

```
NEW scripts/scan-regression.py
  Inputs:  IMAGE_DIR, --baseline <path>, --waivers <path or inline>
  Steps:
    1. Resolve image ref via image.yaml (repo + tag)
    2. grype <ref> -o json → /tmp/scan.json
    3. Extract set of CVE IDs where severity=Critical
    4. Load baseline CVE set from images/<dir>/scan-baseline.json
    5. Load waiver set from images/<dir>/PROMISES.yaml → absence.os-cves.waivers
    6. new_critical = current − baseline − waivered
    7. If new_critical: stderr-report each ("CVE-X: pkg-name version") + exit 1
    8. Else: stdout "scan-regression: ok (N critical in baseline, M waivered)"

NEW scripts/scan-baseline-update.py
  Inputs:  IMAGE_DIR
  Steps:
    Run grype → extract critical CVE IDs → write images/<dir>/scan-baseline.json
    Format: {"version": 1, "critical_cves": [...], "generated_at": ISO-8601, "note": "regenerate with make scan-baseline-update IMAGE_DIR=<dir>"}

NEW images/<name>/scan-baseline.json  (8 pre-generated files)
  Each: zero-CRITICAL baseline (or current-CRITICAL if any exist today)

EXTEND images/<name>/PROMISES.yaml
  Optional `waivers:` list under the absence.os-cves entry:
    - id: absence.os-cves
      description: ...
      waivers:
        - cve: CVE-2026-XXXX
          reason: "no upstream fix; mitigated via <X>"
          until: "2027-01-01"  # ISO date

EXTEND scripts/verify-contracts.py
  For each promise with inverse: true and id matching "absence.os-cves":
    If waivers present: validate each waiver has {cve, reason, until}
    Parse until as date; if past: ERROR "waiver CVE-X expired YYYY-MM-DD"

EXTEND scripts/smart-check.sh (per-affected-image loop)
  After: bash scripts/test-images.sh "${img}"
  Add:   bash scripts/scan-regression.py "${img}"

EXTEND Makefile
  scan-regression:
      @python3 scripts/scan-regression.py "$(IMAGE_DIR)"
  scan-baseline-update:
      @python3 scripts/scan-baseline-update.py "$(IMAGE_DIR)"

EXTEND docs/CAPABILITIES.md
  NEW: scan.regression-gate, scan.cve-waivers
```

## Alternatives rejected

- **Diff vs published `:latest` scan attestation**: catches CVE-DB drift at PR time, but makes PRs flaky (overnight NVD updates cause random reds). Nightly cron is the right place for drift detection.
- **Full grype JSON as baseline (not just CVE IDs)**: 100 KB+ per file × 8 images = noise in every PR diff. CVE-ID set is 10-100x smaller and captures the gating signal.
- **Waiver-via-commit-message**: no audit trail; expires with no enforcement. PROMISES field is the right home.
- **Scan on push-to-dev + fail backward**: too late — the regression is already on dev. Fail at PR time.

## Breaking changes

None. New files + new targets. Existing `make check` gets scan-regression added into the per-image loop via smart-check; existing images are pre-baselined so they pass immediately.

**Exception**: if a current image has an unwaivered CRITICAL we didn't know about, pre-generation will capture it in the baseline (per Q4=a auto-baseline rule) and FG-019 will treat it as the status quo. The baseline files will show the current reality.

## Merge plan

Single PR. Logical commits inside one PR:
1. Mechanism (scripts + verify-contracts extension + Makefile)
2. Baselines (8 scan-baseline.json files from current builds)
3. Smart-check integration
4. Story + plan + acceptance test

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: baseline-equal scan passes | FG-019 acceptance § section 1 | ⏳ |
| Scenario: new CRITICAL fails | § 2 | ⏳ |
| Scenario: waivered CRITICAL passes | § 3 | ⏳ |
| Scenario: expired waiver rejected by verify-contracts | § 4 | ⏳ |
| Scenario: missing baseline auto-bootstraps | § 5 | ⏳ |
| Scenario: smart-check scopes scan-regression per affected image | § 6 | ⏳ |
| 8 baselines pre-generated + committed | `images/*/scan-baseline.json` | ⏳ |
| NEW CAPs registered | `docs/CAPABILITIES.md` | ⏳ |
| `make check-strict` green | local | ⏳ |
