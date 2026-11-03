#!/usr/bin/env bash
#
# Covers: FG-004
# CAPs:   build.central-script, test.central-script,
#         publish.matrix-auto-discovery, publish.ghcr-public-pull,
#         verify.consumer-cmd
#
# Encodes the Gherkin scenarios from
# docs/stories/FG-004-per-variant-ghcr-repos.md.
#
# Red before implementation: image.yamls still carry repo:, docs still
# reference old repo path. Green when all rewrites land.
#
# PUBLISHED=1 enables the sections that require the new GHCR packages to
# exist (external cosign verify, 4-tag → 1 digest resolution).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-004]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

VARIANTS=("python-slim-trixie" "python-scratch-trixie")
TAG="3.13"
ARCH_TAG="3.13-amd64"
LATEST="latest"
LATEST_ARCH="latest-amd64"

# -----------------------------------------------------------------------------
# Section 1 — Scenario: image.yaml drops repo:
# -----------------------------------------------------------------------------
say "1. image.yaml no longer carries a repo: field"
for v in "${VARIANTS[@]}"; do
  f="images/${v}/image.yaml"
  test -f "${f}" || { echo "  ✗ ${f} missing" >&2; exit 1; }
  if grep -qE '^repo:' "${f}"; then
    echo "  ✗ ${f} still has a repo: line — should be derived from dir name" >&2
    exit 1
  fi
done
pass "neither image.yaml carries repo:"

# -----------------------------------------------------------------------------
# Section 2 — Scenario: scripts derive repo from dir name
# -----------------------------------------------------------------------------
say "2. scripts/build-image.sh builds to the repo named after the dir"
for v in "${VARIANTS[@]}"; do
  REGISTRY=forge-local bash scripts/build-image.sh "${v}" >/dev/null
  docker image inspect "forge-local/${v}:${TAG}" >/dev/null
  pass "forge-local/${v}:${TAG} exists"
done

# -----------------------------------------------------------------------------
# Section 3 — Scenario: matrix JSON reflects derived repo
# -----------------------------------------------------------------------------
say "3. scripts/discover-images.sh emits .repo == dir-name"
matrix_json=$(bash scripts/discover-images.sh)
for v in "${VARIANTS[@]}"; do
  found=$(jq -r --arg v "${v}" '.include[] | select(.image_dir == $v) | .repo' <<<"${matrix_json}")
  if [[ "${found}" != "${v}" ]]; then
    echo "  ✗ matrix entry for ${v} has .repo=${found}, expected ${v}" >&2
    exit 1
  fi
done
pass "matrix .repo equals image_dir for both variants"

# -----------------------------------------------------------------------------
# Section 4 — Scenario: no stale python: repo references in docs
# -----------------------------------------------------------------------------
say "4. no stale ghcr.io/bboortz/python: references in docs or README"
# Allow matches inside docs/stories/ and docs/plan/FG-001/2/3 for historical
# accuracy (those commits really did reference the old repo). Check only the
# surfaces consumers read: README + docs/CAPABILITIES + current plan docs.
stale=$(grep -nE 'ghcr\.io/bboortz/python:' README.md docs/CAPABILITIES.md 2>/dev/null || true)
if [[ -n "${stale}" ]]; then
  echo "  ✗ stale references found:" >&2
  echo "${stale}" >&2
  exit 1
fi
pass "no stale repo references in consumer-facing docs"

# -----------------------------------------------------------------------------
# Section 5 — Scenario: design-decisions locks the convention
# -----------------------------------------------------------------------------
say "5. memory/design-decisions.md contains a Repo naming section"
if ! grep -qE '^## .*[Rr]epo naming' memory/design-decisions.md; then
  echo "  ✗ memory/design-decisions.md missing ## Repo naming section" >&2
  exit 1
fi
pass "Repo naming section present"

# -----------------------------------------------------------------------------
# Section 6 — Scenarios requiring published digests (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  for v in "${VARIANTS[@]}"; do
    say "6.${v}. 4-tag family → 1 digest + cosign verify"
    base="ghcr.io/bboortz/${v}"
    # Resolve the digest each tag points at. All 4 must match.
    docker logout ghcr.io 2>/dev/null || true
    digests=()
    for t in "${TAG}" "${ARCH_TAG}" "${LATEST}" "${LATEST_ARCH}"; do
      docker pull "${base}:${t}" >/dev/null
      d=$(docker image inspect --format='{{index .RepoDigests 0}}' "${base}:${t}" | sed 's/.*@//')
      digests+=("${d}")
    done
    uniq=$(printf '%s\n' "${digests[@]}" | sort -u | wc -l)
    if [[ "${uniq}" -ne 1 ]]; then
      echo "  ✗ ${v}: 4 tags resolve to ${uniq} distinct digests (want 1):" >&2
      printf '    %s\n' "${digests[@]}" >&2
      exit 1
    fi
    pass "${v}: :${TAG} / :${ARCH_TAG} / :${LATEST} / :${LATEST_ARCH} all → ${digests[0]:0:16}…"

    cosign verify \
      --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
      --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
      "${base}:${TAG}" >/dev/null
    pass "cosign verify ${base}:${TAG} exits 0"
  done
else
  say "6. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-004 acceptance: all sections passed."
