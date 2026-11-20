#!/usr/bin/env bash
#
# Covers: FG-061
# CAPs:   build.node-slim-base, build.pre-builder-tier, image.forge-rooted-slim-bases

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-061]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/pre-builder/node-slim-trixie/ exists with required files"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json sid-pins \
         tests/smoke_node_version.sh tests/smoke_ca_bundle.sh \
         tests/smoke_dumb_init.sh tests/smoke_apt_upgraded.sh \
         tests/smoke_no_apt_cache.sh tests/smoke_has_shell.sh \
         tests/smoke_size.sh; do
  test -e "images/pre-builder/node-slim-trixie/${f}" \
    || fail "images/pre-builder/node-slim-trixie/${f} missing"
done
pass "node-slim-trixie layout complete"

say "2. node-slim-trixie Dockerfile FROMs node:24-trixie-slim (upstream)"
grep -qE '^FROM node:24-trixie-slim' images/pre-builder/node-slim-trixie/Dockerfile \
  || fail "node-slim-trixie Dockerfile must FROM node:24-trixie-slim"
pass "FROM node:24-trixie-slim present"

say "3. verify-no-upstream-drift: node:24-trixie-slim in anchors + guard clean"
# FG-065 bumped _EXPECTED 5 → 6 (added go-slim-trixie). Here we only assert
# node:24-trixie-slim is still tracked + the guard is green — the exact
# count is FG-065's concern.
grep -q "'node:24-trixie-slim'" scripts/verify-no-upstream-drift.sh \
  || fail "scripts/verify-no-upstream-drift.sh does not list 'node:24-trixie-slim' in _UPSTREAM_ANCHORS"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails — mismatch between _EXPECTED and FROM-grep count"
pass "upstream-drift invariant satisfied"

say "4. discover-images.sh pre-builders mode returns node-slim-trixie"
# Membership assertion only — exact count is FG-065's concern (now 6).
out=$(bash scripts/discover-images.sh pre-builders)
echo "${out}" | jq -e '.include | map(.image_dir) | contains(["node-slim-trixie"])' >/dev/null \
  || fail "pre-builders tier missing node-slim-trixie"
pass "pre-builders tier includes node-slim-trixie"

say "5. uptime-kuma-slim-trixie runtime FROMs \${NODE_SLIM_REF}"
# Previous FG-048c state: runtime stage FROMed node:24-trixie-slim via
# ARG NODE_BASE. FG-061 flips it to FROM ${NODE_SLIM_REF}.
grep -qE '^ARG NODE_SLIM_REF=' images/uptime-kuma-slim-trixie/Dockerfile \
  || fail "uptime-kuma-slim-trixie Dockerfile must declare ARG NODE_SLIM_REF"
# The runtime stage FROM (last FROM line, not the hc or builder stages):
runtime_from=$(awk 'toupper($1)=="FROM"{last=$0} END{print last}' images/uptime-kuma-slim-trixie/Dockerfile)
# shellcheck disable=SC2016  # intentional literal "${NODE_SLIM_REF}" substring
[[ "${runtime_from}" == *'${NODE_SLIM_REF}'* ]] \
  || fail "uptime-kuma-slim-trixie runtime FROM is '${runtime_from}', want '... \${NODE_SLIM_REF}'"
# Belt-and-suspenders: upstream node:24-trixie-slim must NOT be the runtime FROM.
if grep -qE '^FROM node:24-trixie-slim' images/uptime-kuma-slim-trixie/Dockerfile; then
  fail "uptime-kuma-slim-trixie must not FROM node:24-trixie-slim directly (migrated to node-slim-trixie per FG-061)"
fi
pass "uptime-kuma runtime FROMs \${NODE_SLIM_REF}"

say "6. build.yml publish-pre-builders tier comment lists node-slim-trixie"
grep -q "node-slim-trixie" .github/workflows/build.yml \
  || fail ".github/workflows/build.yml must mention node-slim-trixie in the pre-builders tier"
pass "build.yml comment updated"

say "7. Full build + smoke suite (skip in fast-mode)"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1"
else
  FORGE_NO_SKIP=1 bash scripts/build-image.sh pre-builder/node-slim-trixie >/dev/null 2>&1 \
    || fail "node-slim-trixie build failed"
  for s in images/pre-builder/node-slim-trixie/tests/smoke_*.sh; do
    IMAGE_NAME=node-slim-trixie IMAGE_TAG=latest bash "${s}" >/dev/null \
      || fail "smoke failed: ${s}"
  done
  pass "image built + all smokes green"
fi

echo
echo "FG-061 acceptance: all sections passed."
