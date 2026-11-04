#!/usr/bin/env bash
#
# Covers: FG-005
# CAPs:   build.scratch-baseline, test.scratch-contents,
#         image.zero-os-cves, test.size-budget, test.image-smoke-suite
#
# Red before implementation: images/scratch-base-trixie/ absent, python/
# nginx/postgres Dockerfiles still inline their shared closure. Green when
# baseline exists, derivatives COPY from it, and every existing smoke
# test still passes against the refactored images.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-005]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

BASE_DIR="scratch-base-trixie"
BASE_IMAGE="forge-local/${BASE_DIR}:0.1"
DERIVATIVES=(python-scratch-trixie nginx-scratch-trixie postgres-scratch-trixie)

# -----------------------------------------------------------------------------
# Section 1 — baseline scaffolding
# -----------------------------------------------------------------------------
say "1. images/${BASE_DIR}/ in place"
test -f "images/${BASE_DIR}/Dockerfile"
test -f "images/${BASE_DIR}/image.yaml"
test -d "images/${BASE_DIR}/tests"
pass "baseline scaffolding present"

# -----------------------------------------------------------------------------
# Section 2 — baseline builds standalone + smoke suite passes
# -----------------------------------------------------------------------------
say "2. scripts/build-image.sh ${BASE_DIR} builds baseline"
bash scripts/build-image.sh "${BASE_DIR}" >/dev/null
docker image inspect "${BASE_IMAGE}" >/dev/null
pass "${BASE_IMAGE} built"

say "3. baseline smoke suite (file-contents assertions)"
for t in "images/${BASE_DIR}/tests/"smoke_*.sh; do
  bash "${t}"
done

# -----------------------------------------------------------------------------
# Section 4 — each derivative's Dockerfile actually consumes the baseline
# -----------------------------------------------------------------------------
say "4. each scratch derivative derives from scratch-base-trixie"
for d in "${DERIVATIVES[@]}"; do
  df="images/${d}/Dockerfile"
  if ! grep -q 'SCRATCH_BASE_REF' "${df}"; then
    echo "  ✗ ${df} lacks SCRATCH_BASE_REF arg" >&2
    exit 1
  fi
  if ! grep -qE 'COPY --from=scratch_base' "${df}"; then
    echo "  ✗ ${df} lacks COPY --from=scratch_base" >&2
    exit 1
  fi
  if ! grep -qE 'depends_on:' "images/${d}/image.yaml"; then
    echo "  ✗ images/${d}/image.yaml lacks depends_on entry" >&2
    exit 1
  fi
done
pass "all 3 derivatives wired to scratch-base-trixie"

# -----------------------------------------------------------------------------
# Section 5 — each derivative builds (depends_on auto-chains baseline) + smokes green
# -----------------------------------------------------------------------------
say "5. each derivative builds + smoke suite still passes"
for d in "${DERIVATIVES[@]}"; do
  bash scripts/build-image.sh "${d}" >/dev/null
  bash scripts/test-images.sh "${d}" >/dev/null
  pass "${d} builds + smokes green on refactored baseline"
done

# -----------------------------------------------------------------------------
# Section 6 — baseline size is tight
# -----------------------------------------------------------------------------
say "6. baseline image size ≤ 25 MB"
size=$(docker image inspect --format='{{.Size}}' "${BASE_IMAGE}")
if [[ "${size}" -gt 25000000 ]]; then
  echo "  ✗ baseline size ${size} > 25_000_000" >&2
  exit 1
fi
pass "baseline size ${size}B ≤ 25 MB ceiling"

# -----------------------------------------------------------------------------
# Section 7 — differentiators doc explains the baseline layer
# -----------------------------------------------------------------------------
say "7. differentiators.md mentions the baseline"
if ! grep -q 'scratch-base-trixie' docs/differentiators.md; then
  echo "  ✗ docs/differentiators.md doesn't reference scratch-base-trixie" >&2
  exit 1
fi
pass "differentiators.md documents the baseline layer"

echo
echo "FG-005 acceptance: all sections passed."
