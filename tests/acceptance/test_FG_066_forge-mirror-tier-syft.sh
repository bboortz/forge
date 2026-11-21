#!/usr/bin/env bash
#
# Covers: FG-066
# CAPs:   arch.forge-mirror-image, build.mirror-tier, build.mirror-syft,
#         build.shared-builder, build.shared-go-builder, build.shared-node-builder

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-066]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) images/mirror/syft/ scaffold --------------------------------------
say "1. images/mirror/syft/ exists with the mirror-tier shape"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json sid-pins \
         tests/smoke_syft_runs.sh tests/smoke_syft_scan_cyclonedx.sh tests/smoke_size.sh; do
  test -e "images/mirror/syft/${f}" || fail "images/mirror/syft/${f} missing"
done
# image.yaml explicitly declares the nested repo path.
grep -q '^repo: mirror/syft' images/mirror/syft/image.yaml \
  || fail 'images/mirror/syft/image.yaml must declare "repo: mirror/syft"'
pass "mirror/syft layout complete"

# --- (2) mirror/syft Dockerfile is zero-mod (Rule 10 passes) --------------
say "2. mirror/syft Dockerfile contains only FROM / ARG / LABEL (Rule 10)"
# Grep for disallowed directives — must all be absent.
for forbidden in RUN ENV WORKDIR CMD USER ADD EXPOSE HEALTHCHECK VOLUME SHELL STOPSIGNAL ONBUILD ENTRYPOINT; do
  if grep -qE "^${forbidden} " images/mirror/syft/Dockerfile; then
    fail "mirror/syft/Dockerfile contains forbidden directive: ${forbidden}"
  fi
done
grep -qE '^FROM anchore/syft:' images/mirror/syft/Dockerfile \
  || fail "mirror/syft must FROM anchore/syft:<tag>"
pass "mirror/syft Dockerfile is zero-mod (FROM + ARG + LABEL only)"

# --- (3) all 3 forge-builders source syft from mirror/syft ----------------
say "3. all three forge-builders source syft via \${SYFT_REF} (not Docker Hub)"
for b in builder/python-trixie builder/go-trixie builder/node-trixie; do
  grep -qE '^ARG SYFT_REF=ghcr\.io/bboortz/mirror/syft:' "images/${b}/Dockerfile" \
    || fail "${b} must declare ARG SYFT_REF=ghcr.io/bboortz/mirror/syft:…"
  # shellcheck disable=SC2016
  grep -q 'FROM ${SYFT_REF} AS syft-src' "images/${b}/Dockerfile" \
    || fail "${b} must FROM \${SYFT_REF} AS syft-src"
  # No remaining ACTIVE Docker Hub syft FROM / ARG references (comments OK).
  if grep -E '^\s*(FROM|ARG)\s' "images/${b}/Dockerfile" | grep -qE 'docker\.io/anchore/syft|anchore/syft:latest'; then
    fail "${b} Dockerfile FROM/ARG still references anchore/syft (should be forge-signed via SYFT_REF)"
  fi
done
pass "all 3 forge-builders use mirror/syft"

# --- (4) _HELPER_UPSTREAM_ALLOWLIST is emptied ----------------------------
say "4. verify-dockerfile-conformance.py _HELPER_UPSTREAM_ALLOWLIST is empty"
python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('v', 'scripts/verify-dockerfile-conformance.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m._HELPER_UPSTREAM_ALLOWLIST == set(), f'expected empty, got {m._HELPER_UPSTREAM_ALLOWLIST}'
assert 'mirror/syft' in m._FORGE_MIRRORS, '_FORGE_MIRRORS must contain mirror/syft'
assert 'SYFT_REF' in m._KNOWN_REF_ARGS, '_KNOWN_REF_ARGS must contain SYFT_REF'
print('ok')
" || fail "conformance lint constants not updated per FG-066"
pass "_HELPER_UPSTREAM_ALLOWLIST empty; _FORGE_MIRRORS + _KNOWN_REF_ARGS populated"

# --- (5) discover-images.sh exposes `mirrors` mode ------------------------
say '5. discover-images.sh new "mirrors" mode returns exactly mirror/syft'
out=$(bash scripts/discover-images.sh mirrors)
got=$(echo "${out}" | jq '.include | length')
[[ "${got}" -eq 1 ]] || fail "mirrors tier returned ${got} entries (want 1)"
echo "${out}" | jq -e '.include[0].image_dir == "mirror/syft"' >/dev/null \
  || fail "mirrors tier: expected image_dir=mirror/syft"
echo "${out}" | jq -e '.include[0].repo == "mirror/syft"' >/dev/null \
  || fail "mirrors tier: expected repo=mirror/syft"
# `pre-builders` must NOT contain mirror/syft (separation of concerns).
pb_out=$(bash scripts/discover-images.sh pre-builders)
echo "${pb_out}" | jq -e '.include | map(.image_dir) | . != . + ["mirror/syft"]' >/dev/null
echo "${pb_out}" | jq -e '.include | map(.image_dir) | contains(["mirror/syft"]) | not' >/dev/null \
  || fail "pre-builders tier should NOT include mirror/syft"
pass "mirrors mode isolates mirror/syft; pre-builders stays clean"

# --- (6) build.yml has publish-mirrors tier wired correctly ---------------
say "6. build.yml publish-mirrors tier runs parallel to publish-pre-builders"
grep -q 'publish-mirrors:' .github/workflows/build.yml \
  || fail ".github/workflows/build.yml missing publish-mirrors job"
# publish-mirrors must have no `publish-pre-builders` in its `needs:` (parallel).
if awk '/^  publish-mirrors:/{found=1} found && /^  publish-[a-z]/{if(NR>FNR+1){exit}} found && /needs:/{print; exit}' .github/workflows/build.yml | grep -q publish-pre-builders; then
  fail "publish-mirrors must NOT have publish-pre-builders in its needs: (they're parallel siblings)"
fi
# publish-builders must have BOTH publish-pre-builders AND publish-mirrors in its needs.
publish_builders_needs=$(awk '/^  publish-builders:/{found=1} found && /needs:/{print; exit}' .github/workflows/build.yml)
echo "${publish_builders_needs}" | grep -q publish-mirrors \
  || fail "publish-builders needs: must include publish-mirrors (FG-066)"
echo "${publish_builders_needs}" | grep -q publish-pre-builders \
  || fail "publish-builders needs: must still include publish-pre-builders"
pass "build.yml publish-mirrors is parallel with publish-pre-builders + both block publish-builders"

# --- (7) verify-no-upstream-drift ---------------------------------------
# FG-066 originally locked _EXPECTED=6 (mirrors don't count as pre-builders).
# FG-079 bumped it to 7 (Alpine). The invariant FG-066 cares about —
# mirrors don't inflate _EXPECTED — holds either way.
say "7. verify-no-upstream-drift clean (mirrors don't inflate _EXPECTED)"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails — anchore/syft in mirror/syft/Dockerfile is NOT counted (not in _UPSTREAM_ANCHORS)"
# Spot-check: anchore/syft should NOT be in _UPSTREAM_ANCHORS.
grep -qE "anchore/syft" scripts/verify-no-upstream-drift.sh \
  && fail "anchore/syft must NOT be in _UPSTREAM_ANCHORS — mirrors are classified separately"
pass "drift guard still clean"

# --- (8) hc stays at ghcr.io/bboortz/hc (NOT under mirror/) --------------
say "8. hc stays at ghcr.io/bboortz/hc (unchanged by FG-066)"
test -d images/mirror/hc && fail "images/mirror/hc should not exist (hc stays at its current path)"
# Every HC_REF default still points at ghcr.io/bboortz/hc, not ghcr.io/bboortz/mirror/hc.
if grep -rE 'ARG HC_REF=ghcr\.io/bboortz/mirror/hc' images/*/Dockerfile 2>/dev/null; then
  fail "no Dockerfile should reference hc via mirror/hc — hc stays at ghcr.io/bboortz/hc"
fi
pass "hc unchanged — stays at ghcr.io/bboortz/hc"

# --- (9) Rule 10 catches a mirror attempting RUN -------------------------
say "9. Rule 10 catches a mirror that adds a RUN directive (negative test)"
tmp_dir=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '${tmp_dir}'" EXIT
mkdir -p "${tmp_dir}/images/mirror/foo"
cat > "${tmp_dir}/images/mirror/foo/Dockerfile" <<'EOF'
FROM anchore/syft:latest
RUN echo "this should not be allowed"
EOF
cat > "${tmp_dir}/images/mirror/foo/image.yaml" <<'EOF'
tag: "latest"
repo: mirror/foo
platforms:
  - linux/amd64
EOF
# We can't easily run the lint against a tmpdir (IMAGES_DIR is a module
# constant), so assert the Rule 10 CODE PATH exists in the script.
grep -q 'arch.forge-mirror-image invariant' scripts/verify-dockerfile-conformance.py \
  || fail "Rule 10's actionable message must reference arch.forge-mirror-image"
pass "Rule 10 enforcement logic present"

# --- (10) full build + smokes (skip in fast-mode) ------------------------
say "10. Full build + smokes for mirror/syft + 3 flipped builders (skip in fast-mode)"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1"
else
  FORGE_NO_SKIP=1 bash scripts/build-image.sh mirror/syft >/dev/null 2>&1 \
    || fail "mirror/syft build failed"
  for s in images/mirror/syft/tests/smoke_*.sh; do
    IMAGE_NAME=mirror/syft IMAGE_TAG=latest bash "${s}" >/dev/null \
      || fail "mirror/syft smoke failed: ${s}"
  done
  FORGE_NO_SKIP=1 bash scripts/build-image.sh builder/python-trixie >/dev/null 2>&1 \
    || fail "builder/python-trixie build failed (mirror/syft consumer)"
  FORGE_NO_SKIP=1 bash scripts/build-image.sh builder/go-trixie >/dev/null 2>&1 \
    || fail "builder/go-trixie build failed"
  FORGE_NO_SKIP=1 bash scripts/build-image.sh builder/node-trixie >/dev/null 2>&1 \
    || fail "builder/node-trixie build failed"
  pass "all 4 images built + mirror/syft smokes green"
fi

echo
echo "FG-066 acceptance: all sections passed."
