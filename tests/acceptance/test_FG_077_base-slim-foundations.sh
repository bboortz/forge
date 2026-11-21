#!/usr/bin/env bash
#
# Covers: FG-077
# CAPs:   image.debian-slim-foundation, image.ubuntu-slim-foundation, image.node-slim-foundation, arch.base-tier-public-api

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-077]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

NEW_FOUNDATIONS=(debian-slim-trixie ubuntu-slim-noble node-slim-trixie)

# --- (1) 3 new base/*-slim-trixie exist with explicit repo: ---
say "1. 3 new base/*-slim-trixie siblings exist with explicit repo:"
for name in "${NEW_FOUNDATIONS[@]}"; do
  test -d "images/base/${name}" || fail "images/base/${name}/ missing"
  grep -qE "^repo: base/${name}\$" "images/base/${name}/image.yaml" \
    || fail "images/base/${name}/image.yaml missing 'repo: base/${name}'"
done
pass "3 new base/*-slim-trixie present with explicit repo:"

# --- (2) all 3 build + smokes pass ---
say "2. all 3 build + their smokes pass"
for name in "${NEW_FOUNDATIONS[@]}"; do
  bash scripts/build-image.sh "base/${name}" >/dev/null \
    || fail "scripts/build-image.sh base/${name} failed"
  tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' "images/base/${name}/image.yaml")
  docker image inspect "forge-local/base/${name}:${tag}" >/dev/null \
    || fail "forge-local/base/${name}:${tag} did not materialize after build"
  for s in "images/base/${name}/tests/"smoke_*.sh; do
    [[ -f "$s" ]] || continue
    IMAGE_TAG="${tag}" bash "$s" >/dev/null \
      || fail "smoke failed: ${s}"
  done
done
pass "3 new base/*-slim-trixie built + all smokes green"

# --- (3) 4 consumer Dockerfiles flipped to BASE_*_REF ---
say "3. 4 consumer Dockerfiles use BASE_*_REF for final-stage FROM"
# For each consumer, grep the Dockerfile for the new ARG default pointing at base/*.
declare -A CONSUMERS=(
  [github-runner-noble]="BASE_UBUNTU_SLIM_NOBLE_REF.*ghcr.io/bboortz/base/ubuntu-slim-noble"
  [cadvisor-slim-trixie]="BASE_DEBIAN_SLIM_REF.*ghcr.io/bboortz/base/debian-slim-trixie"
  [ipmi-exporter-slim-trixie]="BASE_DEBIAN_SLIM_REF.*ghcr.io/bboortz/base/debian-slim-trixie"
  [uptime-kuma-slim-trixie]="BASE_NODE_SLIM_REF.*ghcr.io/bboortz/base/node-slim-trixie"
)
for consumer in "${!CONSUMERS[@]}"; do
  df="images/${consumer}/Dockerfile"
  test -f "${df}" || fail "images/${consumer}/Dockerfile missing"
  grep -qE "${CONSUMERS[$consumer]}" "${df}" \
    || fail "${consumer}: expected ARG matching '${CONSUMERS[$consumer]}'"
done
pass "4 consumers declare the new BASE_*_REF ARGs"

# --- (3b) No L4 runtime's final FROM resolves to pre-builder/* ---
say "3b. no L4 Dockerfile's final-stage FROM resolves to pre-builder/*"
# Find all images that are neither tier-prefixed nor beaconry (externally-sourced, no local Dockerfile).
_bad=""
for df in images/*/Dockerfile; do
  dir=$(dirname "$df")
  name=${dir#images/}
  # Skip tier-prefixed images (we only audit flat L4 runtimes here).
  case "$name" in
    pre-builder/*|builder/*|base/*|mirror/*) continue ;;
  esac
  # The FINAL FROM is the last FROM in the file.
  final=$(awk 'toupper($1) == "FROM" { last = $2 } END { print last }' "$df")
  case "$final" in
    *PRE_BUILDER*|*SLIM_REF*|*NOBLE_REF*|*SID_REF*)
      # If it's an ARG substitution, resolve it from the Dockerfile.
      arg_name=$(echo "$final" | sed -E 's/^\$\{?([A-Z_]+)\}?$/\1/')
      arg_default=$(awk -v a="$arg_name" '$1=="ARG" && index($2,a)==1 { split($2,p,"="); print p[2] }' "$df")
      if [[ "$arg_default" == *"pre-builder/"* ]]; then
        _bad="${_bad}${name} (final FROM ${final} = ${arg_default})\n"
      fi
      ;;
  esac
done
if [[ -n "$_bad" ]]; then
  printf "%b" "$_bad" >&2
  fail "L4 runtimes still FROM pre-builder/* as final stage (public-API boundary violated)"
fi
pass "no L4 runtime's final FROM resolves to pre-builder/*"

# --- (4) Rule 12 (post-FG-075) passes on 3 new base/* ---
say "4. verify-dockerfile-conformance passes (Rule 12 on all 6 base/*)"
python3 scripts/verify-dockerfile-conformance.py >/dev/null \
  || fail "verify-dockerfile-conformance failed"
pass "conformance green"

# --- (5) verify-no-upstream-drift _EXPECTED=6 (unchanged) ---
say "5. verify-no-upstream-drift stays at _EXPECTED=6"
grep -qE '^_EXPECTED=6$' scripts/verify-no-upstream-drift.sh \
  || fail "verify-no-upstream-drift _EXPECTED must be 6"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails on current fleet"
pass "drift guard green at _EXPECTED=6"

# --- (6) dep graph: all 3 new foundations in L3 subgraph ---
say "6. dep graph L3 subgraph lists all 3 new base/*-slim-trixie"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
for name in "${NEW_FOUNDATIONS[@]}"; do
  node_id="base_${name//-/_}"
  echo "${_graph}" | awk '/subgraph L3_baseline/,/^\s*end\s*$/' \
    | grep -qE "${node_id}\\[\"base/${name}\"\\]:::baseline" \
    || fail "L3 subgraph missing ${node_id}[\"base/${name}\"]:::baseline"
done
pass "all 3 new base/* present in L3 with normalized node ids"

# --- (7) CAPs documented + traceability green ---
say "7. 3 new CAPs documented + traceability green"
for cap in image.debian-slim-foundation image.ubuntu-slim-foundation image.node-slim-foundation; do
  grep -q "^### ${cap}" docs/CAPABILITIES.md \
    || fail "CAPABILITIES missing ### ${cap}"
done
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
pass "3 CAPs registered + traceability green"

echo
echo "FG-077 acceptance: all sections passed."
