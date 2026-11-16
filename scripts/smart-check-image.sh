#!/usr/bin/env bash
# FG-060: per-image build+smoke+scan+accept worker extracted from
# smart-check.sh. Independently callable by xargs for parallel fan-out.
#
# Usage: bash scripts/smart-check-image.sh <image_dir>
#
# Env:
#   FORGE_SKIP_WIPE  — if "1", skip the pre-build `docker rmi forge-local/...`
#   _FORGE_IN_CHECK  — propagated to acceptance tests (FG-017 dedup)
#
# Output: log lines prefixed with [<image>] so parallel runs stay
# attributable in a scrambled stdout.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: smart-check-image.sh <image_dir>" >&2
  exit 2
fi
IMG="$1"
ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

prefix() {
  # shellcheck disable=SC2001  # multi-line awk-style prepend; sed is clearer
  sed "s/^/[${IMG}] /"
}

say() { printf '[%s] %s\n' "${IMG}" "$*"; }
warn() { printf '[%s] ⚠ %s\n' "${IMG}" "$*" >&2; }
fail() { printf '[%s] ✗ %s\n' "${IMG}" "$*" >&2; exit 1; }

iy="images/${IMG}/image.yaml"
[[ -f "${iy}" ]] || fail "missing ${iy}"

# shellcheck source=scripts/_image_yaml.sh disable=SC1091
. scripts/_image_yaml.sh
tag=$(image_yaml_get "${iy}" tag)
repo=$(image_yaml_repo "${iy}")

if [[ "${FORGE_SKIP_WIPE:-0}" != "1" ]]; then
  say "docker rmi forge-local/${repo}:${tag} (cold-cache rebuild for ${IMG})"
  docker rmi "forge-local/${repo}:${tag}" >/dev/null 2>&1 || true
fi

say "build"
bash scripts/build-image.sh "${IMG}" 2>&1 | prefix

say "smoke"
bash scripts/test-images.sh "${IMG}" 2>&1 | prefix

# FG-019: scan-regression gate. Reuses the just-built image.
if command -v grype >/dev/null 2>&1; then
  say "scan-regression"
  python3 scripts/scan-regression.py "${IMG}" 2>&1 | prefix
else
  warn "grype not installed — skipping scan-regression (install via: make tools)"
fi

# Find the matching acceptance test (slug-based).
shopt -s nullglob
accept_tests=(tests/acceptance/test_FG_*_"${IMG#*-}"*.sh)
if [[ ${#accept_tests[@]} -eq 0 ]]; then
  accept_tests=(tests/acceptance/test_FG_*"${IMG}"*.sh)
fi
shopt -u nullglob

for t in "${accept_tests[@]}"; do
  say "acceptance: ${t}"
  _FORGE_IN_CHECK=1 bash "${t}" 2>&1 | prefix
done

say "✓ done"
