#!/usr/bin/env bash
#
# Covers: FG-048
# CAPs:   build.shared-node-builder, build.from-node-source

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-048a]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/forge-builder-node-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml \
         tests/smoke_node_version.sh \
         tests/smoke_corepack_wraps.sh \
         tests/smoke_syft_available.sh; do
  test -e "images/forge-builder-node-trixie/${f}" \
    || fail "images/forge-builder-node-trixie/${f} missing"
done
pass "all required files present"

say "2. forge-builder-node-trixie builds"
bash scripts/build-image.sh forge-builder-node-trixie >/dev/null
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' \
        images/forge-builder-node-trixie/image.yaml)
docker image inspect "forge-local/forge-builder-node-trixie:${tag}" >/dev/null \
  || fail "forge-local/forge-builder-node-trixie:${tag} did not materialize after build"
pass "forge-local/forge-builder-node-trixie:${tag} built"

say "3. Node toolchain + corepack + syft smokes"
for s in images/forge-builder-node-trixie/tests/smoke_*.sh; do
  IMAGE_TAG="${tag}" bash "${s}" >/dev/null
done
pass "all smoke tests green"

say "4. image.yaml invariants: tag=0.1, no depends_on (externally-rooted builder)"
[[ "$tag" == "0.1" ]] || fail "image.yaml tag = '${tag}' (want 0.1)"
if grep -qE '^depends_on:' images/forge-builder-node-trixie/image.yaml; then
  fail "image.yaml should NOT have depends_on (builder base, FROMs upstream node:24-trixie-slim)"
fi
pass "image.yaml correct"

echo
echo "FG-048a acceptance: all sections passed."
