#!/usr/bin/env bash
#
# Covers: FG-072
# CAPs:   build.zig-slim-base, build.shared-zig-builder,
#         build.pre-builder-tier, image.forge-rooted-slim-bases,
#         arch.language-family-image-pair

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-072]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) images/zig-slim-trixie/ layout ------------------------------------
say "1. images/zig-slim-trixie/ exists with the pre-builder shape"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json sid-pins \
         tests/smoke_zig_version.sh tests/smoke_ca_bundle.sh \
         tests/smoke_dumb_init.sh tests/smoke_apt_upgraded.sh \
         tests/smoke_no_apt_cache.sh tests/smoke_has_shell.sh \
         tests/smoke_size.sh; do
  test -e "images/zig-slim-trixie/${f}" \
    || fail "images/zig-slim-trixie/${f} missing"
done
pass "zig-slim-trixie layout complete"

# --- (2) zig-slim-trixie FROMs debian-slim-trixie via ARG-indirect --------
say "2. zig-slim-trixie FROMs \${DEBIAN_SLIM_REF} (not upstream directly)"
grep -qE '^ARG DEBIAN_SLIM_REF=ghcr\.io/bboortz/debian-slim-trixie:(latest|[0-9.]+)' \
  images/zig-slim-trixie/Dockerfile \
  || fail "zig-slim-trixie must declare ARG DEBIAN_SLIM_REF default ghcr.io/bboortz/debian-slim-trixie:…"
runtime_from=$(awk 'toupper($1)=="FROM"{last=$0} END{print last}' images/zig-slim-trixie/Dockerfile)
# shellcheck disable=SC2016
[[ "${runtime_from}" == *'${DEBIAN_SLIM_REF}'* ]] \
  || fail "zig-slim-trixie runtime FROM is '${runtime_from}', want '... \${DEBIAN_SLIM_REF}'"
# Belt-and-suspenders: no literal `FROM debian:trixie-slim`.
if grep -qE '^FROM debian:trixie-slim' images/zig-slim-trixie/Dockerfile; then
  fail "zig-slim-trixie must NOT FROM debian:trixie-slim directly (FG-042 single-upstream-consumer rule)"
fi
pass "zig-slim-trixie FROMs forge-rooted debian-slim-trixie"

# --- (3) zig-slim-trixie installs Zig from ziglang.org via curl + sha256 --
say "3. zig-slim-trixie installs Zig via curl + sha256 verify + untar"
grep -qE '^ARG ZIG_VERSION=' images/zig-slim-trixie/Dockerfile \
  || fail "zig-slim-trixie must declare ARG ZIG_VERSION=..."
grep -qE '^ARG ZIG_SHA256=' images/zig-slim-trixie/Dockerfile \
  || fail "zig-slim-trixie must declare ARG ZIG_SHA256=..."
grep -q 'ziglang.org' images/zig-slim-trixie/Dockerfile \
  || fail "zig-slim-trixie Dockerfile must reference ziglang.org (official tarball)"
grep -q 'sha256sum' images/zig-slim-trixie/Dockerfile \
  || fail "zig-slim-trixie must verify SHA256 of the downloaded tarball"
pass "ziglang.org tarball install + sha256 verify present"

# --- (4) forge-builder-zig-trixie dogfoods zig-slim-trixie ----------------
say "4. forge-builder-zig-trixie dogfoods zig-slim-trixie"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json sid-pins \
         tests/smoke_has_zig.sh tests/smoke_has_syft.sh \
         tests/smoke_ca_bundle.sh tests/smoke_no_apt_cache.sh \
         tests/smoke_release_tools.sh; do
  test -e "images/forge-builder-zig-trixie/${f}" \
    || fail "images/forge-builder-zig-trixie/${f} missing"
done
grep -qE '^ARG ZIG_SLIM_REF=ghcr\.io/bboortz/zig-slim-trixie:(latest|[0-9.]+)' \
  images/forge-builder-zig-trixie/Dockerfile \
  || fail "forge-builder-zig-trixie must declare ARG ZIG_SLIM_REF default ghcr.io/bboortz/zig-slim-trixie:…"
runtime_from=$(awk 'toupper($1)=="FROM"{last=$0} END{print last}' images/forge-builder-zig-trixie/Dockerfile)
# shellcheck disable=SC2016
[[ "${runtime_from}" == *'${ZIG_SLIM_REF}'* ]] \
  || fail "forge-builder-zig-trixie runtime FROM is '${runtime_from}', want '... \${ZIG_SLIM_REF}'"
# Belt-and-suspenders: no literal `FROM debian:trixie-slim` anywhere, and no
# direct FROM to debian-slim-trixie — must go through its own pre-builder.
if grep -qE '^FROM debian:trixie-slim' images/forge-builder-zig-trixie/Dockerfile; then
  fail "forge-builder-zig-trixie must NOT FROM debian:trixie-slim directly"
fi
grep -q 'SYFT_REF' images/forge-builder-zig-trixie/Dockerfile \
  || fail "forge-builder-zig-trixie must COPY syft from \${SYFT_REF} (FG-066 mirror)"
pass "FBZ dogfoods zig-slim-trixie + mirror/syft"

# --- (5) image.yaml depends_on wiring -------------------------------------
say "5. image.yaml depends_on wiring for both images"
grep -q 'debian-slim-trixie' images/zig-slim-trixie/image.yaml \
  || fail "zig-slim-trixie/image.yaml must list debian-slim-trixie in depends_on"
grep -q 'zig-slim-trixie' images/forge-builder-zig-trixie/image.yaml \
  || fail "forge-builder-zig-trixie/image.yaml must list zig-slim-trixie in depends_on"
grep -q 'mirror/syft' images/forge-builder-zig-trixie/image.yaml \
  || fail "forge-builder-zig-trixie/image.yaml must list mirror/syft in depends_on"
pass "depends_on wiring present on both"

# --- (6) pre-builder count 6 → 7, builder count 3 → 4 ---------------------
say "6. discover-images.sh pre-builders = 7, builders = 4"
out=$(bash scripts/discover-images.sh pre-builders)
got=$(echo "${out}" | jq '.include | length')
[[ "${got}" -eq 7 ]] || fail "pre-builders tier returned ${got} entries (want 7)"
echo "${out}" | jq -e '.include | map(.image_dir) | contains(["zig-slim-trixie"])' >/dev/null \
  || fail "pre-builders tier missing zig-slim-trixie"
out=$(bash scripts/discover-images.sh builders)
got=$(echo "${out}" | jq '.include | length')
[[ "${got}" -eq 4 ]] || fail "builders tier returned ${got} entries (want 4)"
echo "${out}" | jq -e '.include | map(.image_dir) | contains(["forge-builder-zig-trixie"])' >/dev/null \
  || fail "builders tier missing forge-builder-zig-trixie"
pass "7 pre-builders + 4 builders including the Zig pair"

# --- (7) verify-no-upstream-drift stays at _EXPECTED=6 --------------------
say "7. verify-no-upstream-drift _EXPECTED stays at 6 (ARG-indirect)"
grep -qE '^_EXPECTED=6$' scripts/verify-no-upstream-drift.sh \
  || fail "scripts/verify-no-upstream-drift.sh _EXPECTED must be 6 (unchanged — Zig uses ARG-indirect FROM)"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails — FG-072 should NOT change literal-FROM-upstream count"
pass "drift guard green at _EXPECTED=6"

# --- (8) arch.language-family-image-pair holds for Zig --------------------
say "8. arch.language-family-image-pair invariant holds for Zig"
grep -q 'zig-slim-trixie' scripts/verify-dockerfile-conformance.py \
  || fail "verify-dockerfile-conformance.py must list zig-slim-trixie in _PRE_BUILDERS"
grep -q 'forge-builder-zig-trixie' scripts/verify-dockerfile-conformance.py \
  || fail "verify-dockerfile-conformance.py must list forge-builder-zig-trixie in _FORGE_BUILDERS"
grep -q 'ZIG_SLIM_REF' scripts/verify-dockerfile-conformance.py \
  || fail "_KNOWN_REF_ARGS must include ZIG_SLIM_REF"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "conformance lint fails against current HEAD (did you forget to register Zig in all three scripts?)"
pass "conformance lint + arch.language-family-image-pair satisfied"

# --- (9) chain depth stays ≤ 5 + dep graph edges exist --------------------
say "9. dep graph contains the new Zig edges"
python3 scripts/image_from_graph.py --emit=mermaid \
  | grep -q 'debian-slim-trixie --> zig-slim-trixie' \
  || fail "dep graph missing debian-slim-trixie → zig-slim-trixie edge"
python3 scripts/image_from_graph.py --emit=mermaid \
  | grep -q 'zig-slim-trixie --> forge-builder-zig-trixie' \
  || fail "dep graph missing zig-slim-trixie → forge-builder-zig-trixie edge"
# Belt-and-suspenders: no direct upstream edge to the Zig images.
if python3 scripts/image_from_graph.py --emit=mermaid | grep -qE 'UP_[A-Z]+ --> zig-slim-trixie'; then
  fail "dep graph has an upstream → zig-slim-trixie edge (must go via debian-slim-trixie)"
fi
pass "dep graph edges correct + no direct upstream edge"

# --- (10) memory + CAPABILITIES updated -----------------------------------
say "10. memory/docs updated for 4 satisfying language families"
grep -q 'zig-slim-trixie' memory/design-decisions.md \
  || fail "memory/design-decisions.md must list zig-slim-trixie in the language family image pairs section"
grep -q 'Zig' memory/design-decisions.md \
  || fail "memory/design-decisions.md must mention Zig in the satisfying families table"
grep -q 'build.zig-slim-base' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing build.zig-slim-base CAP"
grep -q 'build.shared-zig-builder' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing build.shared-zig-builder CAP"
pass "memory + CAPABILITIES document the Zig pair"

# --- (11) Full build + smoke suite (skip in fast-mode) -------------------
say "11. Build + smokes for zig-slim-trixie + forge-builder-zig-trixie (skip in fast-mode)"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1"
else
  FORGE_NO_SKIP=1 bash scripts/build-image.sh zig-slim-trixie >/dev/null 2>&1 \
    || fail "zig-slim-trixie build failed"
  for s in images/zig-slim-trixie/tests/smoke_*.sh; do
    IMAGE_NAME=zig-slim-trixie IMAGE_TAG=latest bash "${s}" >/dev/null \
      || fail "smoke failed: ${s}"
  done
  FORGE_NO_SKIP=1 bash scripts/build-image.sh forge-builder-zig-trixie >/dev/null 2>&1 \
    || fail "forge-builder-zig-trixie build failed (dogfood)"
  for s in images/forge-builder-zig-trixie/tests/smoke_*.sh; do
    IMAGE_NAME=forge-builder-zig-trixie IMAGE_TAG=0.1 bash "${s}" >/dev/null \
      || fail "smoke failed: ${s}"
  done
  pass "both images built + all smokes green"
fi

echo
echo "FG-072 acceptance: all sections passed."
