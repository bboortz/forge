#!/usr/bin/env bash
#
# Covers: FG-002
# CAPs:   test.image-smoke-suite, test.makefile-glob, test.size-budget
#
# Encodes the Gherkin scenarios from
# docs/stories/FG-002-python-image-smoke-suite.md. This test is a *wrapper* —
# it asserts the convention + discovery + aggregate behavior. The actual
# image-contract assertions live as independently-runnable scripts under
# each images/<dir>/tests/.
#
# Red before implementation (no images/*/tests/ dirs → section 1 fails);
# green once dirs, scripts, and `make test-images` all exist.

set -euo pipefail

IMAGE_DIR="python-slim-trixie"
IMAGE_REPO="python"
IMAGE_TAG="3.13-slim-trixie"
TESTS_DIR="images/${IMAGE_DIR}/tests"

cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-002]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — Scenario: Smoke suite lives next to the Dockerfile
# -----------------------------------------------------------------------------
say "1. ${TESTS_DIR}/ exists with ≥ 5 executable .sh files"
test -d "${TESTS_DIR}"
exe_count=$(find "${TESTS_DIR}" -maxdepth 1 -name 'smoke_*.sh' -perm -u+x | wc -l)
if [[ "${exe_count}" -lt 5 ]]; then
  echo "  ✗ expected ≥ 5 executable smoke_*.sh files, found ${exe_count}" >&2
  exit 1
fi
pass "${exe_count} executable smoke scripts present under ${TESTS_DIR}/"

# -----------------------------------------------------------------------------
# Section 2 — Scenario: central test script runs the suite
# -----------------------------------------------------------------------------
say "2. scripts/test-images.sh ${IMAGE_DIR} runs the suite"
make build        IMAGE_DIR="${IMAGE_DIR}" >/dev/null
bash scripts/test-images.sh "${IMAGE_DIR}"
pass "test-images.sh exits 0"

# -----------------------------------------------------------------------------
# Section 3 — Scenario: each smoke script is independently runnable
# -----------------------------------------------------------------------------
say "3. each smoke script is independently runnable"
for t in "${TESTS_DIR}"/smoke_*.sh; do
  IMAGE_NAME="${IMAGE_REPO}" IMAGE_TAG="${IMAGE_TAG}" REGISTRY="forge-local" bash "${t}"
  pass "$(basename "${t}") exits 0"
done

# -----------------------------------------------------------------------------
# Section 4 — Scenario: make check runs test-images
# -----------------------------------------------------------------------------
say "4. Makefile wires test-images into make check"
if ! awk '/^check:/{getline; print; exit}' Makefile | grep -q test-images; then
  echo "  ✗ 'check:' recipe does not include test-images" >&2
  exit 1
fi
pass "make check depends on test-images"

echo
echo "FG-002 acceptance: all sections passed."
