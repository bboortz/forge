#!/usr/bin/env bash
#
# Covers: FG-019
# CAPs:   scan.regression-gate, scan.cve-waivers, tooling.smart-check,
#         contracts.verify-gate
#
# Validates scan-regression.py + waiver mechanism + verify-contracts
# expiry check + smart-check integration, using the live python-scratch
# image + a synthetic fake-scan harness so we don't depend on CVE DB
# updates to trigger a FAIL path.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-019]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

if ! command -v grype >/dev/null 2>&1; then
  echo "  ⚠ grype not installed — skipping FG-019 acceptance (install via: make tools)"
  exit 0
fi

# -----------------------------------------------------------------------------
# Section 1 — every current image has a scan-baseline.json
# -----------------------------------------------------------------------------
say "1. every image has scan-baseline.json"
missing=0
for d in images/*/; do
  name=$(basename "${d}")
  if [[ ! -f "${d}scan-baseline.json" ]]; then
    echo "  ✗ ${name}/scan-baseline.json missing" >&2
    missing=$((missing + 1))
  fi
done
[[ ${missing} -eq 0 ]] || exit 1
pass "all $(find images -maxdepth 1 -mindepth 1 -type d | wc -l) images have scan-baseline.json"

# -----------------------------------------------------------------------------
# Section 2 — scan-regression against unchanged image passes
# -----------------------------------------------------------------------------
say "2. scan-regression on an unchanged image → ok"
bash scripts/build-image.sh python-scratch-trixie >/dev/null
python3 scripts/scan-regression.py python-scratch-trixie >/dev/null
pass "scan-regression: ok on python-scratch-trixie"

# -----------------------------------------------------------------------------
# Section 3 — synthetic new CRITICAL via baseline mutation → FAIL
# -----------------------------------------------------------------------------
say "3. injecting a synthetic missing-from-baseline CRITICAL → FAIL"
# We can't easily inject a real CRITICAL into a built image, so instead we
# TEMPORARILY remove a CVE from the baseline that we claim is in the current
# scan. Since current scan is clean, we need a different approach: write
# a baseline that lists a bogus CVE, then run scan — current scan MISSING a
# baselined CVE is NOT a failure (the gate only flags NEW CVEs, not missing).
#
# Better: use scan-regression.py directly via a test harness that injects
# a fake grype output. We do this by mocking the `run_grype` function:
# write a helper that prepends a fake grype on PATH.
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
cat > "${tmp}/grype" <<'GRYPE'
#!/usr/bin/env bash
# Mock grype that always emits one Critical finding CVE-TEST-0001.
cat <<'JSON'
{
  "matches": [
    {
      "vulnerability": {"id": "CVE-TEST-0001", "severity": "Critical"},
      "artifact": {"name": "fake-pkg", "version": "1.0.0"}
    }
  ]
}
JSON
GRYPE
chmod +x "${tmp}/grype"

set +e
PATH="${tmp}:${PATH}" python3 scripts/scan-regression.py python-scratch-trixie >"${tmp}/out" 2>&1
rc=$?
set -e
if [[ ${rc} -ne 1 ]] || ! grep -q 'CVE-TEST-0001' "${tmp}/out"; then
  echo "  ✗ expected failure on new CRITICAL CVE-TEST-0001 (rc=${rc})" >&2
  cat "${tmp}/out" >&2
  exit 1
fi
pass "new CRITICAL CVE-TEST-0001 → scan-regression FAILed with the CVE id named"

# -----------------------------------------------------------------------------
# Section 4 — same CVE waivered in PROMISES.yaml → scan-regression PASSes
# -----------------------------------------------------------------------------
say "4. waivered CRITICAL via PROMISES.yaml → scan-regression PASSes"
cp images/python-scratch-trixie/PROMISES.yaml "${tmp}/PROMISES.yaml.bak"
python3 - images/python-scratch-trixie/PROMISES.yaml <<'PY'
import sys, yaml, pathlib, datetime
p = pathlib.Path(sys.argv[1])
data = yaml.safe_load(p.read_text())
for promise in data['promises']:
    if promise['id'] == 'absence.os-cves':
        promise['waivers'] = [{
            'cve': 'CVE-TEST-0001',
            'reason': 'FG-019 acceptance test — synthetic CVE',
            'until': (datetime.date.today() + datetime.timedelta(days=30)).isoformat(),
        }]
        break
p.write_text(yaml.safe_dump(data, sort_keys=False))
PY
PATH="${tmp}:${PATH}" python3 scripts/scan-regression.py python-scratch-trixie >/dev/null
pass "waiver (CVE-TEST-0001, until +30d) → scan-regression PASSes"

# -----------------------------------------------------------------------------
# Section 5 — expired waiver → verify-contracts FAILs
# -----------------------------------------------------------------------------
say "5. expired waiver → verify-contracts FAILs"
python3 - images/python-scratch-trixie/PROMISES.yaml <<'PY'
import sys, yaml, pathlib, datetime
p = pathlib.Path(sys.argv[1])
data = yaml.safe_load(p.read_text())
for promise in data['promises']:
    if promise['id'] == 'absence.os-cves':
        promise['waivers'] = [{
            'cve': 'CVE-TEST-0001',
            'reason': 'FG-019 acceptance test — synthetic CVE, expired',
            'until': (datetime.date.today() - datetime.timedelta(days=1)).isoformat(),
        }]
        break
p.write_text(yaml.safe_dump(data, sort_keys=False))
PY
set +e
out=$(python3 scripts/verify-contracts.py 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 1 ]] || ! grep -q 'expired' <<<"${out}"; then
  echo "  ✗ expected verify-contracts to fail on expired waiver (rc=${rc})" >&2
  echo "${out}" >&2
  cp "${tmp}/PROMISES.yaml.bak" images/python-scratch-trixie/PROMISES.yaml
  exit 1
fi
cp "${tmp}/PROMISES.yaml.bak" images/python-scratch-trixie/PROMISES.yaml
pass "verify-contracts rejects expired waiver"

# -----------------------------------------------------------------------------
# Section 6 — missing baseline auto-bootstraps
# -----------------------------------------------------------------------------
say "6. missing baseline auto-bootstraps (Q4=a)"
cp images/python-scratch-trixie/scan-baseline.json "${tmp}/scan-baseline.json.bak"
rm images/python-scratch-trixie/scan-baseline.json
python3 scripts/scan-regression.py python-scratch-trixie >"${tmp}/boot.out" 2>&1
test -f images/python-scratch-trixie/scan-baseline.json || {
  echo "  ✗ expected auto-bootstrap of scan-baseline.json" >&2
  cp "${tmp}/scan-baseline.json.bak" images/python-scratch-trixie/scan-baseline.json
  exit 1
}
grep -q 'auto-bootstrapped' "${tmp}/boot.out" || {
  echo "  ✗ expected 'auto-bootstrapped' message in output" >&2
  cat "${tmp}/boot.out" >&2
  cp "${tmp}/scan-baseline.json.bak" images/python-scratch-trixie/scan-baseline.json
  exit 1
}
cp "${tmp}/scan-baseline.json.bak" images/python-scratch-trixie/scan-baseline.json
pass "missing baseline auto-bootstrapped with current CRITICAL set"

# -----------------------------------------------------------------------------
# Section 7 — smart-check integration: scan-regression runs in scoped loop
# -----------------------------------------------------------------------------
say "7. smart-check scoped loop calls scan-regression per image"
grep -q 'scan-regression.py' scripts/smart-check.sh || {
  echo "  ✗ scripts/smart-check.sh doesn't invoke scan-regression.py" >&2
  exit 1
}
pass "smart-check integrates scan-regression in per-image loop"

echo
echo "FG-019 acceptance: all sections passed."
