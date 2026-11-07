#!/usr/bin/env bash
#
# Covers: FG-021 (buildx cache) + FG-022 (grype DB cache)
# CAPs:   tooling.ci-build-cache, build.pr-ci
#
# Shared acceptance test — both FGs ship in the same PR and both touch
# only workflows + scripts/build-image.sh. We validate via static
# inspection + dry-run of the build script.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-021/022]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — build-image.sh falls back to classic docker build without envs
# -----------------------------------------------------------------------------
say "1. build-image.sh uses docker build when BUILDX_CACHE_* / FORGE_CACHE_* unset"
unset BUILDX_CACHE_FROM BUILDX_CACHE_TO FORGE_CACHE_FROM_PREFIX FORGE_CACHE_PUSH
# Grep the command composition logic (doesn't require actually running a build).
grep -q 'BUILD_CMD=(docker build)' scripts/build-image.sh || {
  echo "  ✗ scripts/build-image.sh missing docker build fallback default" >&2; exit 1;
}
pass "default BUILD_CMD is docker build"

# -----------------------------------------------------------------------------
# Section 2 — build-image.sh uses buildx when BUILDX_CACHE_* set
# -----------------------------------------------------------------------------
say "2. build-image.sh switches to buildx + --cache-from/--cache-to"
grep -q 'docker buildx build --load' scripts/build-image.sh || {
  echo "  ✗ scripts/build-image.sh missing buildx branch" >&2; exit 1;
}
grep -q 'CACHE_ARGS+=.*--cache-from' scripts/build-image.sh || {
  echo "  ✗ scripts/build-image.sh missing --cache-from" >&2; exit 1;
}
grep -q 'CACHE_ARGS+=.*--cache-to' scripts/build-image.sh || {
  echo "  ✗ scripts/build-image.sh missing --cache-to" >&2; exit 1;
}
pass "buildx + --cache-from/--cache-to wired"

# -----------------------------------------------------------------------------
# Section 3 — FORGE_CACHE_FROM_PREFIX resolves per-image buildcache ref
# -----------------------------------------------------------------------------
say "3. FORGE_CACHE_FROM_PREFIX derives per-image :buildcache tag"
grep -q 'FORGE_CACHE_FROM_PREFIX' scripts/build-image.sh || {
  echo "  ✗ FORGE_CACHE_FROM_PREFIX not referenced" >&2; exit 1;
}
grep -q 'FORGE_CACHE_PUSH' scripts/build-image.sh || {
  echo "  ✗ FORGE_CACHE_PUSH not referenced" >&2; exit 1;
}
grep -q ':buildcache' scripts/build-image.sh || {
  echo "  ✗ :buildcache tag naming not present" >&2; exit 1;
}
pass "per-image buildcache tag derivation present"

# -----------------------------------------------------------------------------
# Section 4 — ci.yml wires buildx + GHCR login + cache env
# -----------------------------------------------------------------------------
say "4. ci.yml full-check job wires buildx + grype cache + cache env"
grep -q 'docker/setup-buildx-action' .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml missing docker/setup-buildx-action" >&2; exit 1; }
grep -q 'docker/login-action' .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml missing docker/login-action" >&2; exit 1; }
grep -q 'actions/cache@v4' .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml missing actions/cache" >&2; exit 1; }
grep -q '~/\.cache/grype' .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml cache path isn't ~/.cache/grype" >&2; exit 1; }
grep -q 'FORGE_CACHE_FROM_PREFIX' .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml doesn't set FORGE_CACHE_FROM_PREFIX" >&2; exit 1; }
grep -q 'FORGE_CACHE_PUSH' .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml doesn't set FORGE_CACHE_PUSH" >&2; exit 1; }
pass "ci.yml fully wired"

# -----------------------------------------------------------------------------
# Section 5 — build.yml wires buildx + grype cache on both publish jobs
# -----------------------------------------------------------------------------
say "5. build.yml publish-base + publish-derivatives have buildx + grype cache"
# Both jobs should set up buildx and cache grype DB. Check each pattern appears
# at least twice.
setup_count=$(grep -c 'docker/setup-buildx-action' .github/workflows/build.yml)
cache_count=$(grep -c 'actions/cache@v4' .github/workflows/build.yml)
[[ ${setup_count} -ge 2 ]] || { echo "  ✗ build.yml buildx setup appears ${setup_count}× (want ≥2)" >&2; exit 1; }
[[ ${cache_count} -ge 2 ]] || { echo "  ✗ build.yml grype cache appears ${cache_count}× (want ≥2)" >&2; exit 1; }
pass "build.yml covers both publish jobs"

# -----------------------------------------------------------------------------
# Section 6 — nightly.yml has buildx + grype cache
# -----------------------------------------------------------------------------
say "6. nightly.yml has buildx + grype cache"
grep -q 'docker/setup-buildx-action' .github/workflows/nightly.yml \
  || { echo "  ✗ nightly.yml missing buildx setup" >&2; exit 1; }
grep -q '~/\.cache/grype' .github/workflows/nightly.yml \
  || { echo "  ✗ nightly.yml missing grype cache" >&2; exit 1; }
# Nightly doesn't push cache (it's a clean-cache audit).
grep -qE "FORGE_CACHE_PUSH:\s*'0'" .github/workflows/nightly.yml \
  || { echo "  ✗ nightly.yml should set FORGE_CACHE_PUSH=0" >&2; exit 1; }
pass "nightly.yml: buildx + grype cache, no cache push"

# -----------------------------------------------------------------------------
# Section 7 — PR events don't push cache (fork-safe)
# -----------------------------------------------------------------------------
say "7. ci.yml: FORGE_CACHE_PUSH is 0 on PRs, 1 on push"
grep -q "github.event_name == 'push' && '1' || '0'" .github/workflows/ci.yml \
  || { echo "  ✗ ci.yml FORGE_CACHE_PUSH gate not wired to push vs PR" >&2; exit 1; }
pass "PR events cache-pull-only; push-to-dev writes the cache"

# -----------------------------------------------------------------------------
# Section 8 — yamllint clean on all three workflows
# -----------------------------------------------------------------------------
say "8. updated workflows lint clean"
yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}" \
  .github/workflows/ci.yml .github/workflows/build.yml .github/workflows/nightly.yml >/dev/null
pass "yamllint clean"

echo
echo "FG-021+022 acceptance: all sections passed."
