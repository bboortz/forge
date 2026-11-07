#!/usr/bin/env bash
#
# Covers: FG-017
# CAPs:   tooling.smart-check, tooling.unscoped-lint,
#         test.image-smoke-suite, contracts.verify-gate
#
# Validates smart-check.sh dispatch decisions by making synthetic commits
# on the current branch with --no-verify (fast; no hook cascade), running
# SMART_CHECK_DRY_RUN=1 bash scripts/smart-check.sh _FORGE_BASE_OVERRIDE=<sha>,
# then git-reset-ing the state. Also validates the dedup env + unscoped-lint.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-017]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# If the working tree is dirty, commit a temp checkpoint so synthetic commits
# + hard-resets during this test work against a stable snapshot. Un-commit at
# cleanup so the dev's state is preserved as "uncommitted" afterwards.
_WIP=0
if ! git diff --quiet HEAD -- . 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git add -A
  git -c user.email=fg017@test -c user.name=FG017 commit -q --no-verify -m "FG-017 test checkpoint" >/dev/null
  _WIP=1
fi
BASE_SHA=$(git rev-parse HEAD)

cleanup() {
  cd "$(git rev-parse --show-toplevel)"
  git reset --hard "${BASE_SHA}" >/dev/null 2>&1 || true
  if [[ "${_WIP}" -eq 1 ]]; then
    # Un-commit the checkpoint but keep the content in the working tree.
    git reset --mixed HEAD~1 >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

commit_touch() {
  # Stage files + commit with --no-verify to skip the pre-commit cascade.
  local msg="$1"; shift
  for f in "$@"; do
    [[ -f "$f" ]] || mkdir -p "$(dirname "$f")"
    echo "# FG-017 synth $(date +%s%N)" >> "$f"
  done
  git add "$@"
  git -c user.email=fg017@test -c user.name=FG017 commit -q --no-verify -m "${msg}" >/dev/null
}

# -----------------------------------------------------------------------------
# Section 1 — smart-check.sh exists + dispatches on current branch
# -----------------------------------------------------------------------------
say "1. smart-check.sh present + dispatches"
[[ -x scripts/smart-check.sh ]] || { echo "  ✗ scripts/smart-check.sh missing or not exec" >&2; exit 1; }
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=' <<<"${out}" || { echo "  ✗ smart-check didn't emit DISPATCH= line" >&2; echo "${out}" >&2; exit 1; }
pass "smart-check dispatches"

# -----------------------------------------------------------------------------
# Section 2 — Dedup guards present in the 6 duplicate-smoke acceptance tests
# -----------------------------------------------------------------------------
say "2. _FORGE_IN_CHECK dedup in acceptance tests"
for t in tests/acceptance/test_FG_005_scratch-base-trixie.sh \
         tests/acceptance/test_FG_008_baseline-standard.sh \
         tests/acceptance/test_FG_012_external-sourced-images.sh \
         tests/acceptance/test_FG_013_scout-ref-latest.sh \
         tests/acceptance/test_FG_014_beaconry-hub.sh \
         tests/acceptance/test_FG_015_beaconry-telegram-mock.sh; do
  grep -q '_FORGE_IN_CHECK' "${t}" || { echo "  ✗ ${t} missing dedup guard" >&2; exit 1; }
done
pass "all 6 duplicate-smoke sites carry _FORGE_IN_CHECK"

# -----------------------------------------------------------------------------
# Section 3 — Dispatch: docs-only diff → test-fast-only
# -----------------------------------------------------------------------------
say "3. docs-only diff → test-fast-only"
commit_touch "docs: synth" "docs/fg-017-test-synth.md"
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=test-fast-only' <<<"${out}" || { echo "  ✗ expected test-fast-only; got: ${out}" >&2; exit 1; }
pass "docs/*.md diff → test-fast-only"
git reset --hard "${BASE_SHA}" >/dev/null

# -----------------------------------------------------------------------------
# Section 4 — Dispatch: scratch-base-trixie touched → full bailout
# -----------------------------------------------------------------------------
say "4. scratch-base-trixie touched → full bailout"
commit_touch "baseline: synth" "images/scratch-base-trixie/Dockerfile"
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=full reason=tooling-or-baseline' <<<"${out}" || { echo "  ✗ expected baseline bailout; got: ${out}" >&2; exit 1; }
pass "scratch-base → full bailout"
git reset --hard "${BASE_SHA}" >/dev/null

# -----------------------------------------------------------------------------
# Section 5 — Dispatch: scripts/ change → full bailout
# -----------------------------------------------------------------------------
say "5. scripts/ change → full bailout"
commit_touch "scripts: synth" "scripts/build-image.sh"
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=full reason=tooling-or-baseline' <<<"${out}" || { echo "  ✗ expected scripts bailout; got: ${out}" >&2; exit 1; }
pass "scripts/*.sh → full bailout"
git reset --hard "${BASE_SHA}" >/dev/null

# -----------------------------------------------------------------------------
# Section 6 — Dispatch: 1-image (beaconry-scout) → scoped run
# -----------------------------------------------------------------------------
say "6. single-image diff → scoped dispatch"
commit_touch "scout: synth" "images/beaconry-scout/image.yaml"
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=scoped count=1 images=beaconry-scout' <<<"${out}" || { echo "  ✗ expected scoped scout; got: ${out}" >&2; exit 1; }
pass "images/beaconry-scout/* → scoped (count=1)"
git reset --hard "${BASE_SHA}" >/dev/null

# -----------------------------------------------------------------------------
# Section 7 — Dispatch: >4 images → full bailout
# -----------------------------------------------------------------------------
say "7. >4 images → full bailout"
commit_touch ">4 images: synth" \
  "images/beaconry-scout/image.yaml" \
  "images/beaconry-hub/image.yaml" \
  "images/beaconry-telegram-mock/image.yaml" \
  "images/python-slim-trixie/image.yaml" \
  "images/nginx-scratch-trixie/image.yaml"
out=$(SMART_CHECK_DRY_RUN=1 _FORGE_BASE_OVERRIDE="${BASE_SHA}" bash scripts/smart-check.sh 2>&1)
grep -q 'DISPATCH=full reason=image-count count=5' <<<"${out}" || { echo "  ✗ expected count=5 bailout; got: ${out}" >&2; exit 1; }
pass "5 images → image-count bailout"
git reset --hard "${BASE_SHA}" >/dev/null

# -----------------------------------------------------------------------------
# Section 8 — affected_images.py cascades promise removal via EXPECTATIONS
# -----------------------------------------------------------------------------
say "8. affected_images.py fans out on promise removal"
# Remove a promise from python-scratch-trixie to force cascade.
cp images/python-scratch-trixie/PROMISES.yaml /tmp/py-promises.yaml.bak
python3 - images/python-scratch-trixie/PROMISES.yaml <<'PY'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
data = yaml.safe_load(p.read_text())
# Drop a promise + bump version to major (semver-safe form)
data['promises'] = [pr for pr in data['promises'] if pr['id'] != 'runtime.librt-abi-stub']
data['version'] = '99.0.0'
p.write_text(yaml.safe_dump(data, sort_keys=False))
PY
git add images/python-scratch-trixie/PROMISES.yaml
git -c user.email=fg017@test -c user.name=FG017 commit -q --no-verify -m "python-scratch: promise remove synth" >/dev/null
affected=$(python3 scripts/affected_images.py "${BASE_SHA}" 2>&1 | tr '\n' ' ')
echo "    affected: ${affected}"
[[ "${affected}" == *python-scratch-trixie* ]] || { echo "  ✗ python-scratch-trixie not in affected set" >&2; exit 1; }
if [[ "${affected}" != *beaconry-scout* && "${affected}" != *beaconry-hub* ]]; then
  echo "  ✗ no python-scratch dependent fanned out" >&2
  exit 1
fi
pass "promise removal on python-scratch cascades to dependents"
git reset --hard "${BASE_SHA}" >/dev/null
cp /tmp/py-promises.yaml.bak images/python-scratch-trixie/PROMISES.yaml 2>/dev/null || true
rm -f /tmp/py-promises.yaml.bak

# -----------------------------------------------------------------------------
# Section 9 — unscoped-lint hardening: exec-bit check in Makefile
# -----------------------------------------------------------------------------
say "9. make lint has exec-bit check + uses git ls-files"
grep -q 'missing exec bit' Makefile || { echo "  ✗ Makefile lint missing exec-bit check" >&2; exit 1; }
grep -q 'git ls-files' Makefile || { echo "  ✗ Makefile lint doesn't use git ls-files" >&2; exit 1; }
pass "Makefile lint: exec-bit + git ls-files"

# -----------------------------------------------------------------------------
# Section 10 — pre-commit pre-push hook wired to check-smart-strict
# -----------------------------------------------------------------------------
say "10. pre-commit pre-push → make check-smart-strict"
grep -q 'make check-smart-strict' .pre-commit-config.yaml \
  || { echo "  ✗ pre-commit pre-push doesn't call check-smart-strict" >&2; exit 1; }
pass "pre-push hook wired to check-smart-strict"

# -----------------------------------------------------------------------------
# Section 11 — Makefile exports _FORGE_IN_CHECK on test-acceptance
# -----------------------------------------------------------------------------
say "11. test-acceptance target exports _FORGE_IN_CHECK"
# shellcheck disable=SC2016  # intentional: matching literal Makefile text
grep -q '_FORGE_IN_CHECK=1 bash $$t' Makefile \
  || { echo "  ✗ Makefile test-acceptance doesn't export _FORGE_IN_CHECK" >&2; exit 1; }
pass "_FORGE_IN_CHECK=1 passed down to acceptance tests under make check"

echo
echo "FG-017 acceptance: all sections passed."
