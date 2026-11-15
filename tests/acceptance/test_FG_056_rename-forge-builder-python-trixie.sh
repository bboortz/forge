#!/usr/bin/env bash
#
# Covers: FG-056
# CAPs:   build.shared-builder, build.pre-builder-tier
#
# Pure-refactor acceptance: the old name `forge-builder-trixie` must be gone
# from every LIVE code path (Dockerfiles, scripts, Makefile, CI workflows,
# CAPABILITIES.md, acceptance tests), replaced by `forge-builder-python-trixie`.
#
# Historical plan docs under docs/plan/FG-NNN-*-plan.md and docs/plan/IDEAS.md
# are intentionally NOT asserted — they capture decisions at time of writing
# and must preserve the old name for commit archaeology.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-056]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/forge-builder-python-trixie/ exists; old dir removed"
[[ -d "images/forge-builder-python-trixie" ]] \
  || fail "images/forge-builder-python-trixie/ missing"
[[ ! -d "images/forge-builder-trixie" ]] \
  || fail "images/forge-builder-trixie/ still present — expected rename"
pass "dir renamed"

say "2. PROMISES.yaml carries the new image: name"
grep -qE '^image:[[:space:]]*forge-builder-python-trixie$' \
  images/forge-builder-python-trixie/PROMISES.yaml \
  || fail "PROMISES.yaml: image: field must be forge-builder-python-trixie"
pass "PROMISES.yaml image field = forge-builder-python-trixie"

say "3. No LIVE code path still references the old name"
# Allowed-to-contain-old-name locations (historical / self-ref):
#   - docs/plan/*-plan.md
#   - docs/plan/IDEAS.md
#   - docs/stories/*.md (incl. FG-056's own story describing the rename)
#   - memory/*.md
#   - tests/acceptance/test_FG_056_*.sh (this test's documentation)
#   - .git/
old="forge-builder-trixie"
hits=$(grep -rln "${old}" \
  --include='*.sh' \
  --include='*.yml' --include='*.yaml' \
  --include='Dockerfile' \
  --include='Makefile' \
  --include='*.md' \
  --include='*.py' \
  2>/dev/null \
  | grep -vE '^(docs/plan/|docs/stories/|memory/|tests/acceptance/test_FG_056_|\.git/)' \
  | grep -v '^README.md$' || true)
if [[ -n "${hits}" ]]; then
  echo "  ✗ old name 'forge-builder-trixie' still present in live paths:" >&2
  echo "${hits}" | sed 's/^/    /' >&2
  exit 1
fi
pass "no remaining 'forge-builder-trixie' references in live code"

say "4. Every consumer Dockerfile FROMs the new name"
# Flag any Dockerfile that declares FORGE_BUILDER_REF with the OLD name.
# (Dockerfiles that don't use FORGE_BUILDER_REF at all are fine.)
bad=$(grep -lE "^ARG FORGE_BUILDER_REF=.*/forge-builder-trixie:" \
  images/*/Dockerfile 2>/dev/null || true)
if [[ -n "${bad}" ]]; then
  echo "  ✗ Dockerfiles still reference old builder name:" >&2
  echo "${bad}" | sed 's/^/    /' >&2
  exit 1
fi
# Positive: EVERY consumer that declares FORGE_BUILDER_REF uses the new name.
consumer_count=$(grep -lE "^ARG FORGE_BUILDER_REF=" images/*/Dockerfile 2>/dev/null | wc -l)
new_ref_count=$(grep -lE "^ARG FORGE_BUILDER_REF=.*forge-builder-python-trixie[:@]" images/*/Dockerfile 2>/dev/null | wc -l)
[[ "${consumer_count}" -eq "${new_ref_count}" ]] \
  || fail "FORGE_BUILDER_REF consumer count mismatch: ${new_ref_count}/${consumer_count} use the new name"
pass "all ${consumer_count} FORGE_BUILDER_REF consumers reference forge-builder-python-trixie"

say "5. scripts/discover-images.sh _FORGE_BUILDERS array updated"
grep -qE 'forge-builder-python-trixie[[:space:]]+forge-builder-go-trixie[[:space:]]+forge-builder-node-trixie' \
  scripts/discover-images.sh \
  || fail "scripts/discover-images.sh _FORGE_BUILDERS array must list forge-builder-python-trixie first"
pass "_FORGE_BUILDERS array uses new name"

say "6. scripts/build-image.sh references new dir name"
grep -q "images/forge-builder-python-trixie" scripts/build-image.sh \
  || fail "scripts/build-image.sh does not reference images/forge-builder-python-trixie"
grep -qE "ghcr\.io/bboortz/forge-builder-python-trixie" scripts/build-image.sh \
  || fail "scripts/build-image.sh does not resolve ghcr.io/bboortz/forge-builder-python-trixie"
pass "scripts/build-image.sh references new name in both dir + ghcr ref"

say "7. forge-builder-python-trixie builds + its smokes pass"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1 (fast-mode)"
else
  FORGE_NO_SKIP=1 bash scripts/build-image.sh forge-builder-python-trixie >/dev/null 2>&1 \
    || fail "forge-builder-python-trixie build failed"
  tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' \
    images/forge-builder-python-trixie/image.yaml)
  for smoke in images/forge-builder-python-trixie/tests/smoke_*.sh; do
    IMAGE_NAME=forge-builder-python-trixie IMAGE_TAG="${tag}" bash "${smoke}" >/dev/null \
      || fail "smoke failed: ${smoke}"
  done
  pass "forge-builder-python-trixie built + all smokes green"
fi

echo
echo "FG-056 acceptance: all sections passed."
