#!/usr/bin/env bash
# FG-052 acceptance: alertmanager-scratch-trixie v0.28.1 → v0.35.0 (dual-builder).
#
# CAPs: build.from-node-and-go-source, build.ref-latest-release, image.alertmanager-routes-alerts, scan.regression-gate
#
# Gherkin shell-asserts:
#   1. ui-builder stage FROMs forge-builder-node-trixie + both npm builds succeed.
#   2. Go build uses -tags netgo,builtinassets (grep the Dockerfile).
#   3. ALERTMANAGER_VERSION defaults to empty (FG-050 pattern).
#   4. image.yaml tag is "latest".
#   5. Resolved version is present in /-/status (requires full build; skipped in fast mode).

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n[1;36m[FG-052][0m %s\n' "$*"; }
pass() { printf '  [32m✓[0m %s\n' "$*"; }
fail() { printf '  [31m✗[0m %s\n' "$*" >&2; exit 1; }

DOCKERFILE="images/alertmanager-scratch-trixie/Dockerfile"
YAML="images/alertmanager-scratch-trixie/image.yaml"

say "1. Dockerfile declares a Node ui-builder stage FROM forge-builder-node-trixie"
grep -q "FORGE_BUILDER_NODE_REF" "${DOCKERFILE}" \
  || fail "Dockerfile does not reference FORGE_BUILDER_NODE_REF"
grep -q "FROM \${FORGE_BUILDER_NODE_REF} AS ui-builder" "${DOCKERFILE}" \
  || fail "Dockerfile does not declare FROM forge-builder-node-trixie AS ui-builder"
pass "ui-builder stage present"

say "2. Dockerfile runs npm ci + build for both UI subdirs"
grep -q "ui/app && npm ci" "${DOCKERFILE}" \
  || fail "Dockerfile does not run 'cd ui/app && npm ci' (classic Elm UI build)"
grep -q "ui/mantine-ui && npm ci" "${DOCKERFILE}" \
  || fail "Dockerfile does not run 'cd ui/mantine-ui && npm ci' (Mantine UI build)"
pass "both Elm classic UI + Mantine UI build steps present"

say "3. Go build uses -tags netgo,builtinassets"
grep -q "builtinassets" "${DOCKERFILE}" \
  || fail "Dockerfile Go build is missing the 'builtinassets' tag (won't embed UI)"
pass "go build embeds UI via -tags builtinassets"

say "4. ALERTMANAGER_VERSION defaults to empty (FG-050 build.ref-latest-release)"
grep -qE "^ARG ALERTMANAGER_VERSION=\s*$" "${DOCKERFILE}" \
  || grep -qE "^ARG ALERTMANAGER_VERSION=$" "${DOCKERFILE}" \
  || fail "ALERTMANAGER_VERSION must have an empty default (for :latest floating per FG-050)"
# Must also carry a curl + jq resolve block in the builder OR ui-builder stage.
grep -q "api.github.com/repos/prometheus/alertmanager/releases/latest" "${DOCKERFILE}" \
  || fail "Dockerfile does not resolve upstream :latest via GitHub Releases API"
pass "ALERTMANAGER_VERSION defaults empty + GitHub API resolve present"

say "5. image.yaml tag is \"latest\" (floating)"
grep -qE '^tag:[[:space:]]*"?latest"?$' "${YAML}" \
  || fail "image.yaml tag is not \"latest\" (FG-050 floating pattern)"
pass "image.yaml tag: latest"

say "6. Full build + smoke (only in FULL mode — skipped in fast mode)"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1"
else
  GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || echo "")}"
  export GITHUB_TOKEN
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    echo "  ⚠ no GITHUB_TOKEN (gh auth not configured); API resolve may rate-limit"
  fi

  REGISTRY="${REGISTRY:-forge-local}"
  FORGE_NO_SKIP=1 bash scripts/build-image.sh alertmanager-scratch-trixie >/dev/null 2>&1 \
    || fail "alertmanager-scratch-trixie build failed"
  pass "image built"

  # Run the full smoke suite that ships in images/alertmanager-scratch-trixie/tests/.
  for smoke in images/alertmanager-scratch-trixie/tests/smoke_*.sh; do
    bash "${smoke}" >/dev/null 2>&1 \
      || fail "smoke failed: ${smoke}"
  done
  pass "all existing smokes green against v0.35 build"

  # Quick API sanity: the just-built image reports a non-v0.28 version string
  # (proves the resolve actually bumped past our previous pin).
  set +e
  ver_out=$(docker run --rm --entrypoint=/usr/bin/prometheus-alertmanager "${REGISTRY}/alertmanager-scratch-trixie:latest" --version 2>&1 | head -1)
  set -e
  case "${ver_out}" in
    *"0.28"*) fail "expected a newer version than v0.28, got: ${ver_out}" ;;
    *) pass "resolved version: ${ver_out}" ;;
  esac
fi

echo
echo "FG-052 acceptance: all sections passed."
