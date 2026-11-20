#!/usr/bin/env bash
#
# Covers: FG-058
# CAPs:   build.debian-sid-base, build.pre-builder-tier, image.forge-rooted-slim-bases, scan.cve-waivers

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-058]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. postgres-slim-trixie PROMISES.yaml documents the CVE-2026-6653 waiver"
pp="images/postgres-slim-trixie/PROMISES.yaml"
[[ -f "$pp" ]] || fail "$pp missing"
grep -q "cve: CVE-2026-6653" "$pp" \
  || fail "$pp: expected waiver entry cve: CVE-2026-6653"
grep -q "no-dsa" "$pp" \
  || fail "$pp: waiver reason must reference Debian's <no-dsa> ruling"
grep -q "zero such usage\|zero XML usage\|Homelab postgres" "$pp" \
  || fail "$pp: waiver reason must document homelab reachability"
grep -qE 'until: "202[7-9]-' "$pp" \
  || fail "$pp: waiver until: field must be in the future"
pass "postgres-slim-trixie waiver block present + annotated"

say "2. images/pre-builder/debian-slim-sid/ exists with required files"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json sid-pins \
         tests/smoke_is_sid.sh tests/smoke_ca_bundle.sh \
         tests/smoke_apt_upgraded.sh tests/smoke_no_apt_cache.sh \
         tests/smoke_has_shell.sh tests/smoke_size.sh; do
  test -e "images/pre-builder/debian-slim-sid/${f}" \
    || fail "images/pre-builder/debian-slim-sid/${f} missing"
done
pass "debian-slim-sid layout complete"

say "3. debian-slim-sid Dockerfile FROMs debian:sid-slim"
grep -qE '^FROM debian:sid-slim' images/pre-builder/debian-slim-sid/Dockerfile \
  || fail "debian-slim-sid Dockerfile must FROM debian:sid-slim"
pass "FROM debian:sid-slim present"

say "4. image.yaml tag is \"latest\" (floating per rolling-release)"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/pre-builder/debian-slim-sid/image.yaml)
[[ "$tag" == "latest" ]] || fail "debian-slim-sid image.yaml tag = '${tag}' (want 'latest')"
pass "image.yaml tag correct"

say "5. verify-no-upstream-drift: debian:sid-slim in anchors + guard runs clean"
# FG-058 added debian:sid-slim as the 4th anchor. FG-061 added node:24-trixie-slim
# as the 5th. We assert membership here and let the guard check that _EXPECTED
# tracks the live set of pre-builders — forward-compatible with future additions.
grep -q "'debian:sid-slim'" scripts/verify-no-upstream-drift.sh \
  || fail "scripts/verify-no-upstream-drift.sh does not list 'debian:sid-slim' in _UPSTREAM_ANCHORS"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails — mismatch between _EXPECTED and FROM-grep count"
pass "upstream-drift invariant satisfied (debian:sid-slim anchor present, guard clean)"

say "6. discover-images.sh pre-builders mode includes debian-slim-sid"
out=$(bash scripts/discover-images.sh pre-builders)
echo "${out}" | jq -e '.include | map(.image_dir) | contains(["debian-slim-sid"])' >/dev/null \
  || fail "pre-builders tier missing debian-slim-sid"
pass "pre-builders tier includes debian-slim-sid"

say "7. Full build + smoke suite (skip in fast-mode)"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1"
else
  FORGE_NO_SKIP=1 bash scripts/build-image.sh pre-builder/debian-slim-sid >/dev/null 2>&1 \
    || fail "debian-slim-sid build failed"
  for s in images/pre-builder/debian-slim-sid/tests/smoke_*.sh; do
    IMAGE_NAME=debian-slim-sid IMAGE_TAG=latest bash "${s}" >/dev/null \
      || fail "smoke failed: ${s}"
  done
  pass "image built + all smokes green"
fi

say "8. memory/design-decisions.md documents the Debian sid exception"
grep -q "Exception — Debian sid" memory/design-decisions.md \
  || fail "memory/design-decisions.md missing '## Exception — Debian sid' section (FG-058 precedent)"
pass "design-decisions.md policy present"

echo
echo "FG-058 acceptance: all sections passed."
