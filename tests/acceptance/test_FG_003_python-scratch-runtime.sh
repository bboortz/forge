#!/usr/bin/env bash
#
# Covers: FG-003
# CAPs:   build.two-stage-scratch, image.no-shell, image.zero-os-cves,
#         build.central-script, test.central-script,
#         publish.matrix-auto-discovery
#
# Encodes the Gherkin scenarios from
# docs/stories/FG-003-python-scratch-runtime.md.
#
# Red before implementation: the rename hasn't happened, python-scratch-trixie
# doesn't exist, scripts/build-image.sh is absent, etc. Green once every
# piece lands.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-003]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

SLIM_DIR="images/python-slim-trixie"
SCRATCH_DIR="images/python-scratch-trixie"
OLD_DIR="images/python"

# -----------------------------------------------------------------------------
# Section 1 — Scenario: slim renamed, scratch added
# -----------------------------------------------------------------------------
say "1. image dirs land as expected"
[[ -d "${SLIM_DIR}"    ]] || { echo "  ✗ ${SLIM_DIR} missing" >&2; exit 1; }
[[ -d "${SCRATCH_DIR}" ]] || { echo "  ✗ ${SCRATCH_DIR} missing" >&2; exit 1; }
[[ ! -d "${OLD_DIR}"   ]] || { echo "  ✗ ${OLD_DIR} still exists — rename incomplete" >&2; exit 1; }
[[ -f "${SLIM_DIR}/Dockerfile"    && -f "${SLIM_DIR}/image.yaml"    ]] || { echo "  ✗ slim missing Dockerfile or image.yaml" >&2; exit 1; }
[[ -f "${SCRATCH_DIR}/Dockerfile" && -f "${SCRATCH_DIR}/image.yaml" ]] || { echo "  ✗ scratch missing Dockerfile or image.yaml" >&2; exit 1; }
pass "slim-trixie + scratch dirs present with Dockerfile + image.yaml"

# -----------------------------------------------------------------------------
# Section 2 — Scenario: central build script resolves image.yaml
# -----------------------------------------------------------------------------
say "2. scripts/build-image.sh builds both variants from image.yaml"
[[ -x scripts/build-image.sh ]] || { echo "  ✗ scripts/build-image.sh missing or not executable" >&2; exit 1; }

bash scripts/build-image.sh python-slim-trixie >/dev/null
docker image inspect forge-local/python-slim-trixie:3.13 >/dev/null
pass "forge-local/python-slim-trixie:3.13 built"

bash scripts/build-image.sh python-scratch-trixie >/dev/null
docker image inspect forge-local/python-scratch-trixie:3.13 >/dev/null
pass "forge-local/python-scratch-trixie:3.13 built"

# -----------------------------------------------------------------------------
# Section 3 — Scenario: central test script runs every variant's suite
# -----------------------------------------------------------------------------
say "3. scripts/test-images.sh discovers and runs every suite"
[[ -x scripts/test-images.sh ]] || { echo "  ✗ scripts/test-images.sh missing or not executable" >&2; exit 1; }
bash scripts/test-images.sh
pass "all images/*/tests/smoke_*.sh passed"

# -----------------------------------------------------------------------------
# Section 4 — Scenario: GHA matrix auto-discovers image dirs
# -----------------------------------------------------------------------------
say "4. scripts/discover-images.sh emits a JSON matrix"
[[ -x scripts/discover-images.sh ]] || { echo "  ✗ scripts/discover-images.sh missing or not executable" >&2; exit 1; }
matrix_json=$(bash scripts/discover-images.sh)
jq -e '.include | length >= 2' <<<"${matrix_json}" >/dev/null
jq -e '.include[] | has("image_dir") and has("repo") and has("tag")' <<<"${matrix_json}" >/dev/null
discovered=$(jq -r '.include[].image_dir' <<<"${matrix_json}" | sort | paste -sd,)
pass "matrix contains image_dirs: ${discovered}"

# -----------------------------------------------------------------------------
# Section 5 — Scenario: build.yml wires the matrix to discover-images.sh
# -----------------------------------------------------------------------------
say "5. build.yml consumes the discovered matrix"
if ! grep -q 'discover-images.sh' .github/workflows/build.yml; then
  echo "  ✗ build.yml does not reference discover-images.sh" >&2
  exit 1
fi
pass "build.yml references discover-images.sh"

echo
echo "FG-003 acceptance: all sections passed."
