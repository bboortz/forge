#!/usr/bin/env bash
#
# Covers: FG-042
# CAPs:   build.pre-builder-tier, image.forge-rooted-slim-bases,
#         build.shared-builder (EXT)

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-042]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/debian-slim-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         tests/smoke_ca_bundle.sh tests/smoke_apt_upgraded.sh \
         tests/smoke_no_apt_cache.sh tests/smoke_has_shell.sh \
         tests/smoke_size.sh; do
  test -e "images/debian-slim-trixie/${f}" \
    || fail "images/debian-slim-trixie/${f} missing"
done
pass "all required files present"

say "2. debian-slim-trixie:0.1 builds + smokes pass"
bash scripts/build-image.sh debian-slim-trixie >/dev/null
for s in images/debian-slim-trixie/tests/smoke_*.sh; do
  bash "${s}" >/dev/null
done
pass "debian-slim-trixie:0.1 built + 5 smokes green"

say "3. forge-builder-python-trixie dogfoods python-slim-trixie"
if ! grep -q "PYTHON_SLIM_REF" images/forge-builder-python-trixie/Dockerfile; then
  fail "forge-builder-python-trixie Dockerfile missing PYTHON_SLIM_REF"
fi
if grep -q "DEBIAN_BASE=python:3.14-slim-trixie" images/forge-builder-python-trixie/Dockerfile; then
  fail "forge-builder-python-trixie still references upstream python:3.14-slim-trixie directly"
fi
bash scripts/build-image.sh forge-builder-python-trixie >/dev/null
docker image inspect forge-local/forge-builder-python-trixie:0.1 >/dev/null \
  || fail "forge-builder-python-trixie:0.1 not in daemon after build"
pass "forge-builder-python-trixie FROMs python-slim-trixie"

say "4. cadvisor-slim + ipmi-exporter-slim FROM debian-slim-trixie"
for img in cadvisor-slim-trixie ipmi-exporter-slim-trixie; do
  if ! grep -q "DEBIAN_SLIM_REF" "images/${img}/Dockerfile"; then
    fail "${img} Dockerfile missing DEBIAN_SLIM_REF"
  fi
  if grep -q "DEBIAN_BASE=debian:trixie-slim" "images/${img}/Dockerfile"; then
    fail "${img} still references upstream debian:trixie-slim directly"
  fi
done
bash scripts/build-image.sh cadvisor-slim-trixie >/dev/null
bash scripts/build-image.sh ipmi-exporter-slim-trixie >/dev/null
# Existing smokes must still pass (behavior preservation).
IMAGE_TAG=latest bash images/cadvisor-slim-trixie/tests/smoke_binary_runs.sh >/dev/null
IMAGE_TAG=latest   bash images/ipmi-exporter-slim-trixie/tests/smoke_binary_runs.sh >/dev/null
pass "both FROM debian-slim-trixie + wire-level contract preserved"

say "5. build.yml has 4-tier publish ordering"
if ! grep -q "^  publish-pre-builders:" .github/workflows/build.yml; then
  fail "build.yml missing publish-pre-builders job"
fi
# publish-builders must need publish-pre-builders. FG-066 added publish-mirrors
# as a parallel sibling; it's an additional needs: entry, so match membership
# rather than exact string.
if ! grep -A 2 "^  publish-builders:" .github/workflows/build.yml \
     | grep -q "needs:.*publish-pre-builders"; then
  fail "publish-builders doesn't need publish-pre-builders"
fi
pass "4-tier chain: discover → pre-builders → builders → base → derivatives"

say "6. discover-images.sh pre-builders mode returns the 6 pre-builders"
# FG-051 added ubuntu-slim-noble. FG-058 added debian-slim-sid.
# FG-061 added node-slim-trixie. FG-065 added go-slim-trixie + flipped
# both forge-builders to dogfood their respective pre-builders.
out=$(bash scripts/discover-images.sh pre-builders)
expected_count=6
got=$(echo "${out}" | jq '.include | length')
[[ "${got}" == "${expected_count}" ]] \
  || fail "pre-builders mode returned ${got} entries (want ${expected_count}); output: ${out}"
# Order is alphabetical (per find | sort).
echo "${out}" | jq -e '.include | map(.image_dir) | . == ["debian-slim-sid", "debian-slim-trixie", "go-slim-trixie", "node-slim-trixie", "python-slim-trixie", "ubuntu-slim-noble"]' >/dev/null \
  || fail "pre-builders mode doesn't contain all six pre-builders in the expected order; output: ${out}"
pass "pre-builders mode returns [debian-slim-sid, debian-slim-trixie, go-slim-trixie, node-slim-trixie, python-slim-trixie, ubuntu-slim-noble]"

say "7. upstream grep count collapsed"
# Expect exactly 6 Dockerfiles to FROM the upstream Docker Hub bases:
# the 6 pre-builders. Everything else (including both forge-builders
# post-FG-065) goes through the forge-rooted intermediates.
hits=$(grep -lE '^FROM (debian:trixie-slim|debian:sid-slim|python:3\.14-slim-trixie|ubuntu:24\.04|node:24-trixie-slim|golang:1\.27-trixie)' images/*/Dockerfile 2>&1 | wc -l)
expected=6
[[ "${hits}" == "${expected}" ]] \
  || { echo "  ✗ expected ${expected} Dockerfiles to FROM upstream, got ${hits}:" >&2; \
       grep -lE '^FROM (debian:trixie-slim|debian:sid-slim|python:3\.14-slim-trixie|ubuntu:24\.04|node:24-trixie-slim|golang:1\.27-trixie)' images/*/Dockerfile >&2; \
       exit 1; }
pass "exactly 6 Dockerfiles reference upstream directly (the 6 pre-builders)"

echo
echo "FG-042 acceptance: all sections passed."
