#!/usr/bin/env bash
#
# Covers: FG-025
# CAPs:   build.shared-builder, tooling.ci-build-cache, build.two-stage-scratch
#
# Validates FG-025: a shared builder/python-trixie image exists, carries
# syft + apt-upgrade + CA certs, is published separately in CI, and
# scratch-base-trixie's builder stage FROMs it (not python:3.14-slim-trixie
# directly).

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-025]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — images/builder/python-trixie/ exists with required files
# -----------------------------------------------------------------------------
say "1. builder/python-trixie image dir has the required files"
for f in Dockerfile image.yaml PROMISES.yaml tests/smoke_has_syft.sh tests/smoke_ca_bundle.sh; do
  test -e "images/builder/python-trixie/${f}" \
    || { echo "  ✗ images/builder/python-trixie/${f} missing" >&2; exit 1; }
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — discover-images.sh emits builder/python-trixie in 'builders' mode
#              and excludes it from 'base' mode
# -----------------------------------------------------------------------------
say "2. discover-images.sh: builders mode exposes builder/python-trixie; base excludes it"
bash scripts/discover-images.sh builders | jq -e '.include[] | select(.image_dir == "builder/python-trixie")' >/dev/null \
  || { echo "  ✗ 'builders' mode missing builder/python-trixie" >&2; exit 1; }
if bash scripts/discover-images.sh base | jq -e '.include[] | select(.image_dir == "builder/python-trixie")' >/dev/null 2>&1; then
  echo "  ✗ 'base' mode should NOT include builder/python-trixie" >&2; exit 1
fi
pass "builders/base split correct"

# -----------------------------------------------------------------------------
# Section 3 — scratch-base-trixie's Dockerfile FROMs builder/python-trixie
# -----------------------------------------------------------------------------
say "3. base/scratch-trixie's builder stage uses builder/python-trixie"
grep -q 'ARG BUILDER_PYTHON_REF' images/base/scratch-trixie/Dockerfile \
  || { echo "  ✗ base/scratch-trixie Dockerfile missing BUILDER_PYTHON_REF arg" >&2; exit 1; }
grep -q 'builder/python-trixie' images/base/scratch-trixie/Dockerfile \
  || { echo "  ✗ base/scratch-trixie Dockerfile doesn't reference builder/python-trixie" >&2; exit 1; }
# The apt-upgrade step should be GONE from scratch-base (now in forge-builder)
if grep -q 'apt-get -y --no-install-recommends upgrade' images/base/scratch-trixie/Dockerfile; then
  echo "  ✗ base/scratch-trixie still runs apt-upgrade (should be in forge-builder)" >&2; exit 1
fi
pass "base/scratch-trixie delegates builder-stage boilerplate to builder/python-trixie"

# -----------------------------------------------------------------------------
# Section 4 — build-image.sh pre-builds builder/python-trixie for scratch images
# -----------------------------------------------------------------------------
say "4. build-image.sh triggers builder/python-trixie pre-build for scratch images"
grep -q 'builder-stage dependency: builder/python-trixie' scripts/build-image.sh \
  || { echo "  ✗ build-image.sh missing pre-build hook" >&2; exit 1; }
grep -q 'BUILDER_PYTHON_REF' scripts/build-image.sh \
  || { echo "  ✗ build-image.sh doesn't pass BUILDER_PYTHON_REF build-arg" >&2; exit 1; }
pass "pre-build hook + BUILDER_PYTHON_REF wiring present"

# -----------------------------------------------------------------------------
# Section 5 — build.yml has a publish-builders tier before publish-base
# -----------------------------------------------------------------------------
say "5. build.yml: publish-builders job runs before publish-base"
grep -q '^  publish-builders:' .github/workflows/build.yml \
  || { echo "  ✗ build.yml missing publish-builders job" >&2; exit 1; }
# publish-base must declare 'needs: [discover, publish-builders]' or include publish-builders somehow
grep -A2 '^  publish-base:' .github/workflows/build.yml | grep -q 'publish-builders' \
  || { echo "  ✗ publish-base doesn't 'needs: publish-builders'" >&2; exit 1; }
pass "3-tier publish ordering wired"

# -----------------------------------------------------------------------------
# Section 6 — builder/python-trixie smoke tests pass against the local image
# -----------------------------------------------------------------------------
say "6. builder/python-trixie smoke tests pass (local image)"
if ! docker image inspect forge-local/builder/python-trixie:0.1 >/dev/null 2>&1; then
  echo "  ⚠ forge-local/builder/python-trixie:0.1 not in daemon; building it"
  bash scripts/build-image.sh builder/python-trixie >/dev/null
fi
IMAGE_TAG=0.1 bash images/builder/python-trixie/tests/smoke_has_syft.sh
IMAGE_TAG=0.1 bash images/builder/python-trixie/tests/smoke_ca_bundle.sh
pass "both smoke tests pass"

echo
echo "FG-025 acceptance: all sections passed."
