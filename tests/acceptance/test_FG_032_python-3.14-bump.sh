#!/usr/bin/env bash
#
# Covers: FG-032
# CAPs:   image.python-scratch-nonroot, image.manylinux-wheel-compat,
#         image.ssl-cert-env, build.two-stage-scratch
#
# Validates FG-032: python-scratch-trixie + python-slim-trixie bumped
# in-place from Python 3.13 → 3.14 via Docker Hub's python:3.14-slim-trixie.
# Regression-guards FG-003/009/011/020/031 by re-running them against the
# new images.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-032]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — static invariants
# -----------------------------------------------------------------------------
say "1. source files encode the FG-032 contract"

# Both image.yaml tags are 3.14
for d in python-slim-trixie python-scratch-trixie; do
  tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' "images/${d}/image.yaml")
  [[ "${tag}" == "3.14" ]] || fail "images/${d}/image.yaml: tag=${tag} (want 3.14)"
done

# python-slim-trixie Dockerfile FROMs python:3.14-slim-trixie
grep -qE '^FROM python:3\.14-slim-trixie' images/python-slim-trixie/Dockerfile \
  || fail "python-slim-trixie/Dockerfile: expected FROM python:3.14-slim-trixie"

# python-scratch-trixie Dockerfile parameterizes via ARG PY_VERSION=3.14
# (named PY_VERSION, not PYTHON_VERSION, to avoid colliding with the base
# image's ENV PYTHON_VERSION=3.14.10 which wins over ARG in RUN shells).
grep -qE '^ARG PY_VERSION=3\.14' images/python-scratch-trixie/Dockerfile \
  || fail "python-scratch-trixie/Dockerfile: expected ARG PY_VERSION=3.14"

# No stray 3.13 literal paths in the python-scratch Dockerfile
if grep -nE 'python3\.13|python:3\.13' images/python-scratch-trixie/Dockerfile; then
  fail "python-scratch-trixie/Dockerfile: unexpected 3.13 literal"
fi

# forge-builder-trixie base points at python 3.14 — post-FG-042, the ARG is
# PYTHON_SLIM_REF (dogfood of python-slim-trixie, which itself FROMs
# python:3.14-slim-trixie upstream). The 3.14 version pin is enforced at
# python-slim-trixie's FROM line (checked above on line 30-32).
grep -qE '^ARG PYTHON_SLIM_REF=ghcr\.io/bboortz/python-slim-trixie:' images/forge-builder-trixie/Dockerfile \
  || fail "forge-builder-trixie/Dockerfile: expected ARG PYTHON_SLIM_REF=ghcr.io/bboortz/python-slim-trixie:… (post-FG-042 dogfood)"

pass "all static invariants in place"

# -----------------------------------------------------------------------------
# Section 2 — build
# -----------------------------------------------------------------------------
say "2. build forge-builder-trixie + python-slim-trixie + python-scratch-trixie"
for d in forge-builder-trixie python-slim-trixie python-scratch-trixie; do
  bash scripts/build-image.sh "${d}" >/dev/null
done
docker image inspect forge-local/python-slim-trixie:3.14 >/dev/null
docker image inspect forge-local/python-scratch-trixie:3.14 >/dev/null
pass "both python images built at :3.14"

# -----------------------------------------------------------------------------
# Section 3 — python3 --version reports 3.14
# -----------------------------------------------------------------------------
say "3. runtime interpreter reports Python 3.14"

slim_ver=$(docker run --rm --entrypoint=/usr/local/bin/python3 \
             forge-local/python-slim-trixie:3.14 --version 2>&1)
case "${slim_ver}" in
  "Python 3.14."*) pass "python-slim-trixie: ${slim_ver}" ;;
  *) fail "python-slim-trixie: unexpected --version output: ${slim_ver}" ;;
esac

scratch_ver=$(docker run --rm --entrypoint=/usr/local/bin/python3 \
               forge-local/python-scratch-trixie:3.14 --version 2>&1)
case "${scratch_ver}" in
  "Python 3.14."*) pass "python-scratch-trixie: ${scratch_ver}" ;;
  *) fail "python-scratch-trixie: unexpected --version output: ${scratch_ver}" ;;
esac

# -----------------------------------------------------------------------------
# Section 4 — FG-003/009/011/020/031 regression guards
# -----------------------------------------------------------------------------
say "4. regression suites still green against 3.14"
bash tests/acceptance/test_FG_003_python-scratch-runtime.sh >/dev/null
pass "FG-003 (python-scratch-runtime) passes"
bash tests/acceptance/test_FG_009_python-scratch-hardening.sh >/dev/null
pass "FG-009 (python-scratch-hardening) passes"
bash tests/acceptance/test_FG_011_librt-manylinux-compat.sh >/dev/null
pass "FG-011 (librt-manylinux-compat) passes"
bash tests/acceptance/test_FG_020_sbom-embed.sh >/dev/null
pass "FG-020 (sbom-embed) passes"
bash tests/acceptance/test_FG_031_hc-in-service-images.sh >/dev/null
pass "FG-031 (hc-in-service-images) passes"

# -----------------------------------------------------------------------------
# Section 5 — scan-baseline has been regenerated for 3.14
# -----------------------------------------------------------------------------
say "5. scan-baseline.json carries the 3.14 closure (no drift in-PR)"
# scan-regression.py returns 0 when the baseline matches the current scan.
for d in python-slim-trixie python-scratch-trixie; do
  python3 scripts/scan-regression.py "${d}" >/dev/null 2>&1 \
    || fail "scan-regression against images/${d}/scan-baseline.json fails"
done
pass "both scan baselines match current 3.14 closure"

# -----------------------------------------------------------------------------
# Section 6 — image.yaml invariants (tag + depends_on)
# -----------------------------------------------------------------------------
say "6. image.yaml: tag=3.14, depends_on preserved"
grep -qE '^[[:space:]]*-[[:space:]]*scratch-base-trixie' \
  images/python-scratch-trixie/image.yaml \
  || fail "python-scratch-trixie/image.yaml: depends_on must still list scratch-base-trixie"
pass "python-scratch-trixie depends_on scratch-base-trixie (preserved)"

echo
echo "FG-032 acceptance: all sections passed."
