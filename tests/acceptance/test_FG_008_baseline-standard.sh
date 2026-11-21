#!/usr/bin/env bash
#
# Covers: FG-008
# CAPs:   build.scratch-baseline, test.scratch-contents,
#         docs.baseline-contract, image.zero-os-cves, test.size-budget
#
# Encodes the Gherkin scenarios from docs/stories/FG-008-baseline-standard.md.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-008]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

BASELINE_DIR="base/scratch-trixie"
# FG-084: read tag from image.yaml instead of hard-pinning. Prior-FG pins
# (0.2) block ordinary tag bumps. We still assert the tag exists + looks
# like a 0.x SemVer floor; actual value may bump over time.
BASELINE_TAG=$(awk '/^tag:/ {gsub(/["\x27]/,"",$2); print $2; exit}' "images/${BASELINE_DIR}/image.yaml")
BASELINE_IMAGE="forge-local/${BASELINE_DIR}:${BASELINE_TAG}"

# -----------------------------------------------------------------------------
# Section 1 — baseline tag conforms to 0.x SemVer floor
# -----------------------------------------------------------------------------
say "1. baseline image.yaml tag is a 2-digit 0.x SemVer (floor: 0.2)"
if [[ ! "${BASELINE_TAG}" =~ ^0\.[2-9][0-9]*$ ]]; then
  echo "  ✗ expected 0.x with x >= 2, got: ${BASELINE_TAG}" >&2
  exit 1
fi
pass "image.yaml tag = ${BASELINE_TAG} (>= 0.2 floor)"

# -----------------------------------------------------------------------------
# Section 2 — baseline builds + full smoke suite passes
# -----------------------------------------------------------------------------
say "2. baseline builds + 8 smoke tests pass"
bash scripts/build-image.sh "${BASELINE_DIR}" >/dev/null
docker image inspect "${BASELINE_IMAGE}" >/dev/null
pass "${BASELINE_IMAGE} built"

for t in "images/${BASELINE_DIR}/tests/"smoke_*.sh; do
  bash "${t}"
done
pass "all 8 baseline smokes green"

# -----------------------------------------------------------------------------
# Section 3 — docs/baseline-contract.md exists + documents the API
# -----------------------------------------------------------------------------
say "3. docs/baseline-contract.md published"
test -f docs/baseline-contract.md
for term in 'base/scratch-trixie' 'nonroot' '65532' '65534' 'www-data' 'postgres' \
            'SSL_CERT_FILE' '/etc/services' '/etc/localtime' '/var/tmp' \
            'Composition contract' 'Non-guarantees' 'Reserved UIDs'; do
  if ! grep -q "${term}" docs/baseline-contract.md; then
    echo "  ✗ docs/baseline-contract.md missing required term: ${term}" >&2
    exit 1
  fi
done
pass "baseline-contract.md references every required term"

# -----------------------------------------------------------------------------
# Section 4 — existing scratch derivatives still pass against the current baseline
# -----------------------------------------------------------------------------
say "4. existing derivatives build + smoke green against ${BASELINE_TAG} baseline"
for d in base/python-scratch-trixie nginx-scratch-trixie postgres-scratch-trixie; do
  bash scripts/build-image.sh "${d}" >/dev/null
  # FG-017 B: skip per-derivative smokes under `make check` (test-images runs globally).
  if [[ "${_FORGE_IN_CHECK:-0}" == "1" ]]; then
    pass "${d} builds green on ${BASELINE_TAG} baseline (smokes covered globally)"
  else
    bash scripts/test-images.sh "${d}" >/dev/null
    pass "${d} still passes its own smoke suite on ${BASELINE_TAG} baseline"
  fi
done

# -----------------------------------------------------------------------------
# Section 5 — Post-publish (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "5. external cosign verify against :${BASELINE_TAG} and :latest"
  for t in "${BASELINE_TAG}" latest; do
    cosign verify \
      --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
      --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
      "ghcr.io/bboortz/${BASELINE_DIR}:${t}" >/dev/null
    pass "cosign verify ghcr.io/bboortz/${BASELINE_DIR}:${t}"
  done
else
  say "5. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-008 acceptance: all sections passed."
