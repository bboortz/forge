#!/usr/bin/env bash
#
# Covers: FG-078
# CAPs:   image.psitransfer-slim

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-078]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) image dir layout ---
say "1. images/psitransfer-slim-trixie/ has required files"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json sid-pins tests; do
  test -e "images/psitransfer-slim-trixie/${f}" \
    || fail "images/psitransfer-slim-trixie/${f} missing"
done
# L0.1 registration
grep -q 'github.com/psi-4ward/psitransfer' scripts/_upstream_sources.py \
  || fail "scripts/_upstream_sources.py missing github.com/psi-4ward/psitransfer entry"
pass "layout complete + L0.1 registered"

# --- (2) builds + smokes pass ---
say "2. psitransfer-slim-trixie:latest builds + smokes pass"
bash scripts/build-image.sh psitransfer-slim-trixie >/dev/null \
  || fail "scripts/build-image.sh psitransfer-slim-trixie failed"
docker image inspect forge-local/psitransfer-slim-trixie:latest >/dev/null \
  || fail "forge-local/psitransfer-slim-trixie:latest did not materialize"
for s in images/psitransfer-slim-trixie/tests/smoke_*.sh; do
  [[ -f "$s" ]] || continue
  bash "$s" >/dev/null \
    || fail "smoke failed: ${s}"
done
pass "built + all smokes green"

# --- (3) Dockerfile FROM chain ---
say "3. Dockerfile FROMs builder/node-trixie (build) + base/node-slim-trixie (runtime)"
grep -qE 'FROM \$\{BUILDER_NODE_REF\}' images/psitransfer-slim-trixie/Dockerfile \
  || fail "Dockerfile must FROM \${BUILDER_NODE_REF} in a build stage"
grep -qE 'FROM \$\{BASE_NODE_SLIM_REF\}' images/psitransfer-slim-trixie/Dockerfile \
  || fail "Dockerfile must FROM \${BASE_NODE_SLIM_REF} in the runtime stage"
pass "chain correct (build on builder/node-trixie, runtime on base/node-slim-trixie)"

# --- (4) image.yaml declares depends_on base/node-slim-trixie ---
say "4. image.yaml depends_on base/node-slim-trixie"
grep -qE '^\s*-\s*base/node-slim-trixie\s*$' images/psitransfer-slim-trixie/image.yaml \
  || fail "image.yaml must declare depends_on base/node-slim-trixie (FG-077 publish-ordering)"
pass "depends_on correct"

# --- (5) verify-no-upstream-drift unchanged (_EXPECTED=6) ---
say "5. verify-no-upstream-drift stays at _EXPECTED=6"
grep -qE '^_EXPECTED=6$' scripts/verify-no-upstream-drift.sh \
  || fail "verify-no-upstream-drift _EXPECTED must be 6"
bash scripts/verify-no-upstream-drift.sh >/dev/null \
  || fail "verify-no-upstream-drift fails"
pass "drift guard green"

# --- (6) dep graph includes psitransfer under L4 + source edge from L0.1 ---
say "6. dep graph: psitransfer-slim-trixie in L4 + L0.1 source edge"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${_graph}" | grep -q 'psitransfer-slim-trixie:::' \
  || fail "dep graph missing psitransfer-slim-trixie L4 node"
echo "${_graph}" | grep -qE 'SRC_GH_PSI_4WARD_PSITRANSFER.*psitransfer-slim-trixie' \
  || fail "dep graph missing L0.1 psi-4ward/psitransfer → psitransfer-slim-trixie edge"
pass "dep graph edges present"

# --- (7) CAP documented + traceability green ---
say "7. CAP + traceability"
grep -q '^### image.psitransfer-slim' docs/CAPABILITIES.md \
  || fail "CAPABILITIES missing ### image.psitransfer-slim"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability check failed"
pass "CAP registered + traceability green"

echo
echo "FG-078 acceptance: all sections passed."
