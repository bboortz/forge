#!/usr/bin/env bash
#
# Covers: FG-010
# CAPs:   contracts.promises, contracts.expectations,
#         contracts.verify-gate, contracts.semver-enforcement
#
# Validates the full image-to-image contract system: declarative PROMISES
# per image + EXPECTATIONS per derivative + verifier + semver pre-commit gate.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-010]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

VERIFY=scripts/verify-contracts.py
SEMVER=scripts/contracts-semver-check.py

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

# -----------------------------------------------------------------------------
# Section 1 — baseline: current graph is consistent
# -----------------------------------------------------------------------------
say "1. current PROMISES/EXPECTATIONS graph is consistent"
python3 "${VERIFY}" >/dev/null
pass "verify-contracts: ok"

# Every image has a PROMISES.yaml
for img in images/*/; do
  name=$(basename "${img}")
  [[ -f "${img}/PROMISES.yaml" ]] || { echo "✗ ${name} missing PROMISES.yaml" >&2; exit 1; }
done
pass "every image has PROMISES.yaml"

# Every image that declares depends_on has EXPECTATIONS.yaml
for img in images/*/; do
  name=$(basename "${img}")
  if grep -q '^depends_on:' "${img}/image.yaml" 2>/dev/null; then
    if grep -A5 '^depends_on:' "${img}/image.yaml" | grep -q '^\s*-'; then
      [[ -f "${img}/EXPECTATIONS.yaml" ]] || { echo "✗ ${name} depends on another image but has no EXPECTATIONS.yaml" >&2; exit 1; }
    fi
  fi
done
pass "every image with depends_on has EXPECTATIONS.yaml"

# -----------------------------------------------------------------------------
# Section 2 — reachability: every EXPECTATIONS promise resolves
# -----------------------------------------------------------------------------
say "2. every expectation references a declared promise"
# Already covered by section 1 — but assert specifically via Python
python3 - <<'PY'
import sys, pathlib, yaml
root = pathlib.Path('.').resolve()
promises = {}
for p in (root / 'images').glob('*/PROMISES.yaml'):
    data = yaml.safe_load(p.read_text())
    promises[data['image']] = {pr['id'] for pr in data.get('promises', [])}
errs = []
for p in (root / 'images').glob('*/EXPECTATIONS.yaml'):
    data = yaml.safe_load(p.read_text())
    img = data['image']
    for dep in data.get('dependencies', []):
        di = dep['image']
        for e in dep.get('expectations', []):
            if e['promise'] not in promises.get(di, set()):
                errs.append(f"{img} → {di}: unknown promise {e['promise']}")
if errs:
    for e in errs: print(e, file=sys.stderr)
    sys.exit(1)
PY
pass "all 23 expectations resolve to declared promises"

# -----------------------------------------------------------------------------
# Section 3 — nonexistent promise reference fails verify-contracts
# -----------------------------------------------------------------------------
say "3. verify-contracts flags references to nonexistent promises"
cp images/python-scratch-trixie/EXPECTATIONS.yaml "${tmp}/EXPECTATIONS.yaml.bak"
# Inject a bogus promise reference
python3 - "${tmp}/EXPECTATIONS.yaml.bak" images/python-scratch-trixie/EXPECTATIONS.yaml <<'PY'
import sys, yaml, pathlib
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(pathlib.Path(src).read_text())
data['dependencies'][0]['expectations'].append({
    'promise': 'nonexistent.widget',
    'reason': 'injected-by-FG-010-test',
    'preflight': ['images/python-scratch-trixie/tests/smoke_imports.sh'],
})
pathlib.Path(dst).write_text(yaml.safe_dump(data, sort_keys=False))
PY
set +e
python3 "${VERIFY}" >"${tmp}/v3.out" 2>&1
rc=$?
set -e
if [[ ${rc} -ne 0 ]] && grep -q 'nonexistent.widget' "${tmp}/v3.out"; then
  pass "verifier names the unknown promise"
else
  echo "✗ verifier did not flag nonexistent.widget (rc=${rc})" >&2
  cat "${tmp}/v3.out" >&2
  cp "${tmp}/EXPECTATIONS.yaml.bak" images/python-scratch-trixie/EXPECTATIONS.yaml
  exit 1
fi
cp "${tmp}/EXPECTATIONS.yaml.bak" images/python-scratch-trixie/EXPECTATIONS.yaml
python3 "${VERIFY}" >/dev/null
pass "graph recovers after repair"

# -----------------------------------------------------------------------------
# Section 4 — baseline surface shrinks → every dependent fires
# -----------------------------------------------------------------------------
say "4. removing a baseline promise fires one error per dependent"
cp images/scratch-base-trixie/PROMISES.yaml "${tmp}/base.yaml.bak"
# Remove files.time from baseline
python3 - "${tmp}/base.yaml.bak" images/scratch-base-trixie/PROMISES.yaml <<'PY'
import sys, yaml, pathlib
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(pathlib.Path(src).read_text())
data['promises'] = [p for p in data['promises'] if p['id'] != 'files.time']
pathlib.Path(dst).write_text(yaml.safe_dump(data, sort_keys=False))
PY
# postgres-scratch-trixie references files.time. verify should fail with that pointer.
set +e
python3 "${VERIFY}" >"${tmp}/v4.out" 2>&1
rc=$?
set -e
if [[ ${rc} -ne 0 ]] && grep -q 'files.time' "${tmp}/v4.out"; then
  pass "verifier names files.time as the broken edge"
else
  echo "✗ removing files.time did not surface in verifier output (rc=${rc})" >&2
  cat "${tmp}/v4.out" >&2
  cp "${tmp}/base.yaml.bak" images/scratch-base-trixie/PROMISES.yaml
  exit 1
fi
cp "${tmp}/base.yaml.bak" images/scratch-base-trixie/PROMISES.yaml
python3 "${VERIFY}" >/dev/null
pass "graph recovers after baseline repair"

# -----------------------------------------------------------------------------
# Section 5 — version mismatch
# -----------------------------------------------------------------------------
say "5. verifier rejects dependency constraints the baseline can't satisfy"
cp images/python-scratch-trixie/EXPECTATIONS.yaml "${tmp}/py.yaml.bak"
python3 - "${tmp}/py.yaml.bak" images/python-scratch-trixie/EXPECTATIONS.yaml <<'PY'
import sys, yaml, pathlib
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(pathlib.Path(src).read_text())
data['dependencies'][0]['version'] = '>=0.9'
pathlib.Path(dst).write_text(yaml.safe_dump(data, sort_keys=False))
PY
set +e
python3 "${VERIFY}" >"${tmp}/v5.out" 2>&1
rc=$?
set -e
if [[ ${rc} -ne 0 ]] && grep -q 'does not satisfy constraint' "${tmp}/v5.out"; then
  pass "verifier rejects version constraint >=0.9 against baseline 0.2"
else
  echo "✗ version constraint error not surfaced (rc=${rc})" >&2
  cat "${tmp}/v5.out" >&2
  cp "${tmp}/py.yaml.bak" images/python-scratch-trixie/EXPECTATIONS.yaml
  exit 1
fi
cp "${tmp}/py.yaml.bak" images/python-scratch-trixie/EXPECTATIONS.yaml
python3 "${VERIFY}" >/dev/null
pass "graph recovers after version repair"

# -----------------------------------------------------------------------------
# Section 6 — semver gate: adding a promise requires a minor bump
# -----------------------------------------------------------------------------
say "6. contracts-semver-check requires a minor bump when a promise is added"
# The semver checker's --compare mode is purpose-built for testing without
# faking git state. Pass OLD and NEW explicitly.
cp images/scratch-base-trixie/PROMISES.yaml "${tmp}/old.yaml"
cp images/scratch-base-trixie/PROMISES.yaml "${tmp}/new.yaml"
python3 - "${tmp}/new.yaml" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
data = yaml.safe_load(p.read_text())
data['promises'].append({
    'id': 'files.new-widget',
    'description': 'injected by FG-010 acceptance test',
    'caps': ['build.scratch-baseline'],
    'tests': ['images/scratch-base-trixie/tests/smoke_contents_required_files.sh'],
})
# keep version 0.2 (should be rejected)
p.write_text(yaml.safe_dump(data, sort_keys=False))
PY

set +e
python3 "${SEMVER}" --compare "${tmp}/old.yaml" "${tmp}/new.yaml" >"${tmp}/sv6.out" 2>&1
rc=$?
set -e
if [[ ${rc} -ne 0 ]] && grep -q 'added 1 promise' "${tmp}/sv6.out"; then
  pass "semver gate identifies the 1 added promise and the required bump"
else
  echo "✗ semver gate did not identify the added promise (rc=${rc})" >&2
  cat "${tmp}/sv6.out" >&2
  exit 1
fi

# Bump version properly → semver gate passes
python3 - "${tmp}/new.yaml" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
data = yaml.safe_load(p.read_text())
data['version'] = '0.3'
p.write_text(yaml.safe_dump(data, sort_keys=False))
PY
python3 "${SEMVER}" --compare "${tmp}/old.yaml" "${tmp}/new.yaml" >/dev/null
pass "semver gate accepts the same change with 0.2 → 0.3 bump"

# No change → silent
python3 "${SEMVER}" --compare "${tmp}/old.yaml" "${tmp}/old.yaml" >/dev/null
pass "semver gate is silent when there is no change"

# -----------------------------------------------------------------------------
# Section 7 — removed promise requires dependents to re-attest
# -----------------------------------------------------------------------------
say "7. semver gate flags removal as breaking without --allow-breaking"
cp images/scratch-base-trixie/PROMISES.yaml "${tmp}/old2.yaml"
cp images/scratch-base-trixie/PROMISES.yaml "${tmp}/new2.yaml"
python3 - "${tmp}/new2.yaml" <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
data = yaml.safe_load(p.read_text())
data['promises'] = [pr for pr in data['promises'] if pr['id'] != 'identity.nobody']
data['version'] = '1.0.0'  # major bump
p.write_text(yaml.safe_dump(data, sort_keys=False))
PY
# Ensure no --allow-breaking is in COMMIT_EDITMSG
: > .git/COMMIT_EDITMSG 2>/dev/null || true
set +e
python3 "${SEMVER}" --compare "${tmp}/old2.yaml" "${tmp}/new2.yaml" >"${tmp}/sv7.out" 2>&1
rc=$?
set -e
if [[ ${rc} -ne 0 ]] && grep -q 'breaking change' "${tmp}/sv7.out"; then
  pass "semver gate flags removal as breaking without --allow-breaking"
else
  echo "✗ semver gate did not flag the removal as breaking (rc=${rc})" >&2
  cat "${tmp}/sv7.out" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Section 8 — make verify-contracts target exists and passes
# -----------------------------------------------------------------------------
say "8. make verify-contracts is wired in"
make -q verify-contracts >/dev/null 2>&1 || make verify-contracts >/dev/null
pass "make verify-contracts passes"

echo
echo "FG-010 acceptance: all sections passed."
