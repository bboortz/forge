#!/usr/bin/env bash
#
# Covers: FG-069
# CAPs:   build.base-tier, arch.base-tier-images

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-069]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) new paths exist + old paths gone ---
say "1. new base/ paths exist + old flat paths gone"
test -d images/base/scratch-trixie || fail "images/base/scratch-trixie missing"
test -d images/base/python-trixie  || fail "images/base/python-trixie missing"
test ! -e images/scratch-base-trixie || fail "images/scratch-base-trixie still exists"
test ! -e images/python-scratch-trixie || fail "images/python-scratch-trixie still exists"
# Full contract set in new locations (EXPECTATIONS only for images with deps).
for name in scratch-trixie python-trixie; do
  for req in Dockerfile image.yaml PROMISES.yaml scan-baseline.json sid-pins tests; do
    test -e "images/base/${name}/${req}" \
      || fail "images/base/${name}/${req} missing"
  done
done
# python-trixie depends on scratch-trixie, so it must have EXPECTATIONS; scratch-trixie has no deps so no EXPECTATIONS.
test -f images/base/python-trixie/EXPECTATIONS.yaml \
  || fail "images/base/python-trixie/EXPECTATIONS.yaml missing"
pass "base/ layout complete; old paths gone"

# --- (2) PROMISES image: fields use leaf names ---
say "2. PROMISES image: fields are leaf names (mirror/syft convention)"
grep -qE '^image: scratch-trixie$' images/base/scratch-trixie/PROMISES.yaml \
  || fail "scratch-trixie/PROMISES.yaml: image: must be 'scratch-trixie' (not base/scratch-trixie)"
grep -qE '^image: python-trixie$' images/base/python-trixie/PROMISES.yaml \
  || fail "python-trixie/PROMISES.yaml: image: must be 'python-trixie'"
grep -qE '^image: python-trixie$' images/base/python-trixie/EXPECTATIONS.yaml \
  || fail "python-trixie/EXPECTATIONS.yaml: image: must be 'python-trixie'"
pass "PROMISES image: fields correct"

# --- (3) 9 scratch-runtime Dockerfiles' ARG default updated ---
say "3. ARG SCRATCH_BASE_REF defaults point at base/scratch-trixie"
_bad=$(grep -l 'ARG SCRATCH_BASE_REF=ghcr\.io/bboortz/scratch-base-trixie' images/*/Dockerfile images/base/*/Dockerfile 2>/dev/null || true)
[[ -z "${_bad}" ]] || { echo "${_bad}" >&2; fail "stale ARG defaults still reference ghcr.io/bboortz/scratch-base-trixie"; }
# Also assert the new default is present in ≥ 9 Dockerfiles.
_n=$(grep -l 'ARG SCRATCH_BASE_REF=ghcr\.io/bboortz/base/scratch-trixie:latest' images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null | wc -l)
[[ "${_n}" -ge 9 ]] || fail "only ${_n} Dockerfiles updated to base/scratch-trixie:latest default (want ≥ 9)"
pass "ARG defaults updated across ${_n} Dockerfiles"

# --- (4) image.yaml depends_on entries updated ---
say "4. image.yaml depends_on entries flipped to new paths"
_offenders=$(grep -lE '^\s+- (scratch-base-trixie|python-scratch-trixie)$' images/*/image.yaml images/base/*/image.yaml 2>/dev/null || true)
[[ -z "${_offenders}" ]] || { echo "${_offenders}" >&2; fail "stale depends_on entries remain"; }
# Count new-path refs.
_scratch_consumers=$(grep -lE '^\s+- base/scratch-trixie$' images/*/image.yaml images/base/*/image.yaml 2>/dev/null | wc -l)
_python_consumers=$(grep -lE '^\s+- base/python-trixie$' images/*/image.yaml images/base/*/image.yaml 2>/dev/null | wc -l)
[[ "${_scratch_consumers}" -ge 9 ]] || fail "only ${_scratch_consumers} images depend on base/scratch-trixie (want ≥ 9)"
[[ "${_python_consumers}" -ge 3 ]] || fail "only ${_python_consumers} images depend on base/python-trixie (want ≥ 3)"
pass "${_scratch_consumers} + ${_python_consumers} = $((_scratch_consumers + _python_consumers)) depends_on entries updated"

# --- (5) EXPECTATIONS cross-refs updated ---
say "5. EXPECTATIONS files' image/preflight refs updated"
_bad_img=$(grep -lE '^\s+- image: (scratch-base-trixie|python-scratch-trixie)$' images/*/EXPECTATIONS.yaml images/base/*/EXPECTATIONS.yaml 2>/dev/null || true)
[[ -z "${_bad_img}" ]] || { echo "${_bad_img}" >&2; fail "stale image: dep refs in EXPECTATIONS"; }
_bad_preflight=$(grep -lE 'images/(scratch-base-trixie|python-scratch-trixie)/tests/' images/*/EXPECTATIONS.yaml images/base/*/EXPECTATIONS.yaml images/*/PROMISES.yaml images/base/*/PROMISES.yaml 2>/dev/null || true)
[[ -z "${_bad_preflight}" ]] || { echo "${_bad_preflight}" >&2; fail "stale preflight paths in PROMISES/EXPECTATIONS"; }
pass "EXPECTATIONS clean"

# --- (6) Rule 12: negative + positive ---
say "6. Rule 12 — base/ images FROM scratch + have ≥ 1 forge-internal consumer"
grep -q 'Rule 12' scripts/verify-dockerfile-conformance.py \
  || fail "scripts/verify-dockerfile-conformance.py missing Rule 12"
# Positive: current fleet passes.
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "conformance lint fails on current HEAD (Rule 12 false-positive?)"
# Negative: synthetic bad base/.
_tmp=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '${_tmp}'" EXIT
# Copy ONLY the base/ dirs — Rule 12 specifically checks base/<name>/ existence.
# Make a minimal images/ tree + add a bad base/ entry.
mkdir -p "${_tmp}/images/base/bad"
cat > "${_tmp}/images/base/bad/Dockerfile" <<'EOF'
FROM python:3.14-slim-trixie
EOF
cat > "${_tmp}/images/base/bad/image.yaml" <<'EOF'
tag: "0.1"
platforms: [linux/amd64]
EOF
set +e
out=$(FORGE_IMAGES_DIR="${_tmp}/images" python3 scripts/verify-dockerfile-conformance.py 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  echo "${out}" >&2
  fail "Rule 12 did not fire on synthetic base/bad (non-scratch FROM + zero consumers)"
fi
echo "${out}" | grep -qE 'Rule 12|base/bad' \
  || { echo "${out}" >&2; fail "failure message didn't flag Rule 12 / base/bad"; }
pass "Rule 12 fires on synthetic base/bad; fleet passes"

# --- (7) discover-images classification ---
say "7. discover-images.sh places base/ entries correctly"
bash scripts/discover-images.sh base 2>&1 | jq -e '.include | map(.image_dir) | contains(["base/scratch-trixie"])' >/dev/null \
  || fail "discover-images.sh base mode doesn't contain base/scratch-trixie"
bash scripts/discover-images.sh derivatives 2>&1 | jq -e '.include | map(.image_dir) | contains(["base/python-trixie"])' >/dev/null \
  || fail "discover-images.sh derivatives mode doesn't contain base/python-trixie"
pass "discover-images classification correct"

# --- (8) dep graph renders both base/ images at L3 ---
say "8. dep graph: both base/ images under L3 subgraph with :::baseline styling"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${_graph}" | awk '/subgraph L3_baseline/,/^    end$/' | grep -q 'base/scratch-trixie:::baseline' \
  || fail "L3 subgraph missing base/scratch-trixie:::baseline"
echo "${_graph}" | awk '/subgraph L3_baseline/,/^    end$/' | grep -q 'base/python-trixie:::baseline' \
  || fail "L3 subgraph missing base/python-trixie:::baseline"
# Also NOT in L4 as slim.
echo "${_graph}" | awk '/subgraph L4_runtimes/,/^    end$/' | grep -qE 'base/(scratch|python)-trixie' \
  && fail "base/ image leaked into L4 subgraph"
pass "L3 baseline subgraph has both base/ nodes"

# --- (9) verify-* all green ---
say "9. verify-* gates all green on current HEAD"
python3 scripts/verify-dockerfile-conformance.py >/dev/null || fail "conformance lint failed"
python3 scripts/verify-contracts.py >/dev/null || fail "contracts verify failed"
python3 scripts/verify-source-inventory.py >/dev/null || fail "source inventory verify failed"
bash scripts/verify-no-upstream-drift.sh >/dev/null || fail "upstream drift check failed"
bash scripts/verify-image-dirs.sh >/dev/null || fail "image-dirs check failed"
pass "all verify-* gates green"

# --- (10) traceability green with new CAPs ---
say "10. new CAPs documented + traceability green"
grep -q '^### build.base-tier' docs/CAPABILITIES.md || fail "CAPABILITIES missing ### build.base-tier"
grep -q '^### arch.base-tier-images' docs/CAPABILITIES.md || fail "CAPABILITIES missing ### arch.base-tier-images"
bash scripts/verify-traceability.sh >/dev/null || fail "traceability check failed"
pass "CAPs registered + traceability green"

# --- (11) memory + docs reference new paths + Rule 12 ---
say "11. memory/docker-standard.md references Rule 12 + new paths"
grep -q 'Rule 12' memory/docker-standard.md || fail "memory/docker-standard.md missing Rule 12"
grep -q 'base/scratch-trixie' memory/docker-standard.md || fail "memory missing base/scratch-trixie"
grep -q 'base/python-trixie' memory/docker-standard.md || fail "memory missing base/python-trixie"
pass "memory updated"

echo
echo "FG-069 acceptance: all sections passed."
