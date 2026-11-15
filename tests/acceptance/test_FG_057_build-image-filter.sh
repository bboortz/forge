#!/usr/bin/env bash
#
# Covers: FG-057
# CAPs:   build.workflow-dispatch-image-filter, build.daily-publish, publish.matrix-auto-discovery
#
# Exercises scripts/discover-images.sh --filter directly (no GHA runner needed).

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-057]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# Helper — count .include[] entries in the JSON output.
count_include() {
  jq -r '.include | length'
}
include_dirs() {
  jq -r '.include[].image_dir' | sort
}

say "1. filter=all (default — cron behaviour unchanged)"
out=$(bash scripts/discover-images.sh all --filter all)
n=$(echo "${out}" | count_include)
images_total=$(find images -mindepth 1 -maxdepth 1 -type d -name '*-*' | wc -l)
[[ "${n}" -eq "${images_total}" ]] \
  || fail "filter=all returned ${n} entries, want ${images_total} (= dir count)"
pass "filter=all returns all ${n} images"

say "2. filter=all split by tier equals all images"
for mode in pre-builders builders base derivatives; do
  bash scripts/discover-images.sh "${mode}" --filter all >/dev/null \
    || fail "mode=${mode} --filter=all failed"
done
pass "every tier mode accepts --filter=all"

say "3. filter=beaconry-hub matches exactly one image"
out=$(bash scripts/discover-images.sh all --filter "beaconry-hub")
dirs=$(echo "${out}" | include_dirs)
[[ "${dirs}" == "beaconry-hub" ]] \
  || fail "filter=beaconry-hub matched: '${dirs}' (want 'beaconry-hub')"
pass "filter=beaconry-hub returns exactly {beaconry-hub}"

say "4. filter=beaconry-hub,beaconry-scout matches both"
out=$(bash scripts/discover-images.sh all --filter "beaconry-hub,beaconry-scout")
dirs=$(echo "${out}" | include_dirs | tr '\n' ',' | sed 's/,$//')
[[ "${dirs}" == "beaconry-hub,beaconry-scout" ]] \
  || fail "comma-filter matched: '${dirs}' (want 'beaconry-hub,beaconry-scout')"
pass "comma-list filter returns both entries"

say "5. glob filter 'beaconry-*' matches the family"
out=$(bash scripts/discover-images.sh all --filter "beaconry-*")
dirs=$(echo "${out}" | include_dirs)
# Expect beaconry-hub, beaconry-scout, beaconry-telegram-mock (and possibly more that start with beaconry-).
expected=$(find images -maxdepth 1 -mindepth 1 -type d -name 'beaconry-*' -printf '%f\n' | sort)
[[ "${dirs}" == "${expected}" ]] \
  || fail "glob 'beaconry-*' matched '${dirs}' (want '$(echo "${expected}" | tr '\n' ' ')')"
pass "glob filter 'beaconry-*' returns the full family"

say "6. glob filter 'prometheus-*' matches only prometheus images"
out=$(bash scripts/discover-images.sh all --filter "prometheus-*")
dirs=$(echo "${out}" | include_dirs)
expected=$(find images -maxdepth 1 -mindepth 1 -type d -name 'prometheus-*' -printf '%f\n' | sort)
[[ "${dirs}" == "${expected}" ]] \
  || fail "glob 'prometheus-*' matched '${dirs}' (want '$(echo "${expected}" | tr '\n' ' ')')"
pass "glob filter 'prometheus-*' returns prometheus images"

say "7. filter + tier intersection: beaconry-hub belongs to derivatives tier only"
# pre-builders tier filtered to beaconry-hub → empty (beaconry-hub isn't a pre-builder)
pb=$(bash scripts/discover-images.sh pre-builders --filter "beaconry-hub" | count_include)
[[ "${pb}" -eq 0 ]] \
  || fail "pre-builders+beaconry-hub returned ${pb} (want 0 — beaconry-hub isn't a pre-builder)"
# derivatives tier filtered to beaconry-hub → exactly 1 (beaconry-hub IS a derivative via depends_on)
der=$(bash scripts/discover-images.sh derivatives --filter "beaconry-hub" | count_include)
[[ "${der}" -eq 1 ]] \
  || fail "derivatives+beaconry-hub returned ${der} (want 1)"
pass "tier × filter intersection correct"

say "8. nonexistent image fails fast"
set +e
err=$(bash scripts/discover-images.sh all --filter "does-not-exist" 2>&1 >/dev/null)
rc=$?
set -e
[[ "${rc}" -ne 0 ]] \
  || fail "expected nonzero exit for nonexistent image; got 0"
echo "${err}" | grep -qiE "zero|no match|not found|does-not-exist" \
  || fail "expected an error mentioning the no-match reason; got: ${err}"
pass "nonexistent filter fails fast with clear error"

say "9. empty-match glob fails fast"
set +e
err=$(bash scripts/discover-images.sh all --filter "xyz-definitely-nonexistent-*" 2>&1 >/dev/null)
rc=$?
set -e
[[ "${rc}" -ne 0 ]] \
  || fail "expected nonzero exit for empty glob; got 0"
pass "empty-glob filter fails fast"

say "10. build.yml exposes workflow_dispatch.inputs.images"
grep -qE 'workflow_dispatch:' .github/workflows/build.yml \
  || fail "build.yml missing workflow_dispatch section"
grep -qE '^\s{4,}inputs:' .github/workflows/build.yml \
  || fail "build.yml workflow_dispatch missing inputs: block"
grep -qE '^\s{6,}images:' .github/workflows/build.yml \
  || fail "build.yml missing inputs.images"
grep -qE "default:\s*['\"]?all['\"]?" .github/workflows/build.yml \
  || fail "build.yml inputs.images missing default: all"
pass "build.yml exposes workflow_dispatch.inputs.images with default=all"

echo
echo "FG-057 acceptance: all sections passed."
