#!/usr/bin/env bash
#
# Covers: FG-023
# CAPs:   build.stamp-skip, tooling.ci-build-cache, tooling.smart-check
#
# Validates stamp-based rebuild skip: scripts/build-image.sh writes a
# stamp per image on build; a second invocation with identical inputs
# skips docker build; stamp invalidates on Dockerfile edit, upstream
# FROM digest change (simulated), baseline image ID change, FORGE_NO_SKIP=1,
# and make check-strict wipes stamps.
#
# Uses python-slim-trixie as the test target because it's small + fast to
# rebuild on cache miss and has no scratch-base dependency complications.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-023]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE_DIR="python-slim-trixie"
STAMP="/tmp/forge-stamp-$$"
BUILD_LOG="/tmp/forge-build-$$"
trap 'rm -rf "${STAMP}" "${BUILD_LOG}" .make/stamps/_fg023_test_* 2>/dev/null' EXIT

# -----------------------------------------------------------------------------
# Section 0 — stamp helper exists + emits deterministic hex
# -----------------------------------------------------------------------------
say "0. scripts/stamp-image.sh emits a deterministic SHA-256"
test -x scripts/stamp-image.sh || {
  echo "  ✗ scripts/stamp-image.sh missing or not executable" >&2; exit 1;
}
S1=$(bash scripts/stamp-image.sh "${IMAGE_DIR}")
S2=$(bash scripts/stamp-image.sh "${IMAGE_DIR}")
[[ "${S1}" == "${S2}" ]] || {
  echo "  ✗ stamp is not deterministic: ${S1} vs ${S2}" >&2; exit 1;
}
# SHA-256 hex is 64 chars
[[ ${#S1} -eq 64 ]] || {
  echo "  ✗ stamp is not 64-char hex: ${S1}" >&2; exit 1;
}
pass "stamp deterministic (${S1:0:12}…)"

# -----------------------------------------------------------------------------
# Section 1 — build writes stamp; re-run on identical inputs skips docker build
# -----------------------------------------------------------------------------
say "1. second build with identical inputs skips docker build"
rm -rf ".make/stamps/${IMAGE_DIR}.stamp"
# First build — must build normally
bash scripts/build-image.sh "${IMAGE_DIR}" > "${BUILD_LOG}" 2>&1
test -f ".make/stamps/${IMAGE_DIR}.stamp" || {
  echo "  ✗ stamp file not written after build" >&2; cat "${BUILD_LOG}" >&2; exit 1;
}
pass "first build wrote .make/stamps/${IMAGE_DIR}.stamp"

# Second build — must skip docker build
bash scripts/build-image.sh "${IMAGE_DIR}" > "${BUILD_LOG}" 2>&1
grep -q "stamp-skip:" "${BUILD_LOG}" || {
  echo "  ✗ second build did not skip; expected 'stamp-skip:' in output" >&2
  tail -20 "${BUILD_LOG}" >&2; exit 1;
}
pass "second build skipped docker build"

# -----------------------------------------------------------------------------
# Section 2 — Dockerfile edit invalidates stamp
# -----------------------------------------------------------------------------
say "2. editing images/<dir>/Dockerfile invalidates the stamp"
S_BEFORE=$(bash scripts/stamp-image.sh "${IMAGE_DIR}")
# Non-semantic edit (append a comment) using a scratch copy; avoid real changes
cp "images/${IMAGE_DIR}/Dockerfile" "/tmp/forge-dockerfile-$$.bak"
echo "# FG-023 test — temporary" >> "images/${IMAGE_DIR}/Dockerfile"
S_AFTER=$(bash scripts/stamp-image.sh "${IMAGE_DIR}")
mv "/tmp/forge-dockerfile-$$.bak" "images/${IMAGE_DIR}/Dockerfile"
[[ "${S_BEFORE}" != "${S_AFTER}" ]] || {
  echo "  ✗ stamp did not change after Dockerfile edit" >&2; exit 1;
}
pass "Dockerfile edit → stamp changed (${S_BEFORE:0:8}… → ${S_AFTER:0:8}…)"

# -----------------------------------------------------------------------------
# Section 3 — FORGE_NO_SKIP=1 bypasses stamp
# -----------------------------------------------------------------------------
say "3. FORGE_NO_SKIP=1 forces a build regardless of stamp"
# Guaranteed stamp hit (just ran build in section 1)
FORGE_NO_SKIP=1 bash scripts/build-image.sh "${IMAGE_DIR}" > "${BUILD_LOG}" 2>&1
grep -q "stamp-skip:" "${BUILD_LOG}" && {
  echo "  ✗ FORGE_NO_SKIP=1 still skipped the build" >&2
  tail -20 "${BUILD_LOG}" >&2; exit 1;
}
pass "FORGE_NO_SKIP=1 triggered rebuild"

# -----------------------------------------------------------------------------
# Section 4 — removing the daemon image invalidates the skip
# -----------------------------------------------------------------------------
say "4. docker rmi on the image forces rebuild even when stamp matches"
# Fast setup: the image is in daemon, stamp is current (just wrote it)
REPO=$(python3 -c "import yaml; d=yaml.safe_load(open('images/${IMAGE_DIR}/image.yaml')); print(d.get('repo', '${IMAGE_DIR}'))")
TAG=$(python3 -c "import yaml; d=yaml.safe_load(open('images/${IMAGE_DIR}/image.yaml')); print(d['tag'])")
docker rmi "forge-local/${REPO}:${TAG}" >/dev/null 2>&1 || true
bash scripts/build-image.sh "${IMAGE_DIR}" > "${BUILD_LOG}" 2>&1
grep -q "stamp-skip:" "${BUILD_LOG}" && {
  echo "  ✗ skipped despite image not in daemon" >&2
  tail -20 "${BUILD_LOG}" >&2; exit 1;
}
pass "docker rmi forces rebuild (stamp hit but daemon miss → build)"

# -----------------------------------------------------------------------------
# Section 5 — make check-strict wipes stamps
# -----------------------------------------------------------------------------
say "5. make check-strict wipes .make/stamps/"
# Create a sentinel stamp (test-only) then verify clean-stamps wipes
mkdir -p .make/stamps
echo "test-sentinel" > .make/stamps/_fg023_test_sentinel.stamp
make clean-stamps >/dev/null 2>&1
test ! -f .make/stamps/_fg023_test_sentinel.stamp || {
  echo "  ✗ make clean-stamps did not remove test stamp" >&2; exit 1;
}
# Also verify clean-stamps is a prerequisite of check-strict (via Makefile grep)
grep -qE "^check-strict:.*clean-stamps|^check-strict:.*clean" Makefile || {
  echo "  ✗ check-strict target does not include clean-stamps" >&2
  grep "^check-strict:" Makefile >&2; exit 1;
}
pass "clean-stamps target wipes .make/stamps/ and is a check-strict prereq"

# -----------------------------------------------------------------------------
# Section 6 — stamp includes upstream FROM digest (resolved fresh)
# -----------------------------------------------------------------------------
say "6. stamp changes when upstream FROM digest changes (simulated)"
# We simulate by passing a FAKE_FROM_DIGEST env that stamp-image.sh reads to
# override the real resolve for test purposes. Script must honor it.
S_REAL=$(bash scripts/stamp-image.sh "${IMAGE_DIR}")
S_FAKE=$(FAKE_FROM_DIGEST=sha256:deadbeef bash scripts/stamp-image.sh "${IMAGE_DIR}")
[[ "${S_REAL}" != "${S_FAKE}" ]] || {
  echo "  ✗ stamp did not change when FROM digest injected" >&2; exit 1;
}
pass "FROM-digest override changes stamp (upstream-change detection works)"

echo
echo "FG-023 acceptance: all sections passed."
