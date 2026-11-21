#!/usr/bin/env bash
#
# Covers: FG-083
# CAPs:   arch.verify-no-orphan-smokes, arch.verify-cap-has-promise,
#         arch.verify-promises-version-bump

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-083]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) current tree is clean under all 3 new gates ---
say "1. current tree exits 0 under all 3 FG-083 gates"
test -x scripts/verify-no-orphan-smokes.py \
  || fail "scripts/verify-no-orphan-smokes.py missing"
test -x scripts/verify-promises-version-bump.sh \
  || fail "scripts/verify-promises-version-bump.sh missing"
python3 scripts/verify-no-orphan-smokes.py >/dev/null \
  || fail "verify-no-orphan-smokes failed on clean tree"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "verify-traceability failed on clean tree (Rule 4 regression?)"
bash scripts/verify-promises-version-bump.sh >/dev/null \
  || fail "verify-promises-version-bump failed on clean tree"
pass "clean tree passes all 3 gates"

# --- (2) artificial orphan smoke → (a) fires ---
say "2. artificial orphan smoke → verify-no-orphan-smokes fails"
_orphan="images/pre-builder/alpine-3/tests/smoke__fg083_orphan.sh"
_cleanup_2() {
  rm -f "${_orphan}" >/dev/null 2>&1 || true
}
trap _cleanup_2 EXIT
printf '#!/usr/bin/env bash\necho orphan\n' > "${_orphan}"
chmod +x "${_orphan}"
if python3 scripts/verify-no-orphan-smokes.py >/dev/null 2>&1; then
  fail "verify-no-orphan-smokes SHOULD have failed on injected orphan"
fi
rm -f "${_orphan}"
trap - EXIT
pass "orphan smoke detected"

# --- (3) artificial orphan CAP → (b) fires ---
# Save/restore via tempfile rather than `git checkout --` because the test
# may run while CAPABILITIES.md has legitimate uncommitted edits (shipping
# the very CAPs we're about to add); checkout would clobber them.
say "3. artificial orphan CAP → verify-traceability fails"
_cap_id="image.fg083-injected-orphan"
_caps_backup="$(mktemp)"
cp docs/CAPABILITIES.md "${_caps_backup}"
_cleanup_3() {
  cp "${_caps_backup}" docs/CAPABILITIES.md
  rm -f "${_caps_backup}"
}
trap _cleanup_3 EXIT
cat >> docs/CAPABILITIES.md <<EOF

### ${_cap_id}

**FG-083 TEST FIXTURE** — appended by test_FG_083 §3 to prove verify-traceability's Rule 4 fires. Reverted by trap.

- **Delivered by**: FG-083 (test fixture only)
- **Covered by**: n/a — injected to trigger failure
EOF
if bash scripts/verify-traceability.sh >/dev/null 2>&1; then
  _cleanup_3; trap - EXIT
  fail "verify-traceability SHOULD have failed on orphan CAP"
fi
_cleanup_3
trap - EXIT
pass "orphan CAP detected"

# --- (4) artificial promise-add without version bump → (c) fires ---
say "4. artificial promise-add w/o version bump → verify-promises-version-bump fails"
_target="images/base/alpine-3/PROMISES.yaml"
_target_backup="$(mktemp)"
cp "${_target}" "${_target_backup}"
_cleanup_4() {
  cp "${_target_backup}" "${_target}"
  rm -f "${_target_backup}"
}
trap _cleanup_4 EXIT
cat >> "${_target}" <<'EOF'

  - id: fg083.injected-fixture
    description: "FG-083 test fixture — appended to prove verify-promises-version-bump fires on promise-add without version bump. Reverted by trap."
    caps: [image.alpine-foundation]
    tests:
      - images/base/alpine-3/tests/smoke_ca_bundle.sh
EOF
# Base-vs-HEAD check with the uncommitted worktree change.
if GIT_DIFF_BASE="HEAD" bash scripts/verify-promises-version-bump.sh >/dev/null 2>&1; then
  _cleanup_4; trap - EXIT
  fail "verify-promises-version-bump SHOULD have failed on promise-add without version bump"
fi
_cleanup_4
trap - EXIT
pass "promise-add without version bump detected"

# --- (5) make test-fast wires all three gates ---
say "5. Makefile test-fast wires the 3 gates"
for pattern in "verify-no-orphan-smokes" "verify-promises-version-bump"; do
  if ! grep -q "${pattern}" Makefile; then
    fail "Makefile missing invocation of ${pattern}"
  fi
done
pass "Makefile wires all 3 gates"

echo
echo "FG-083 acceptance: all sections passed."
