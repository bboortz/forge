#!/usr/bin/env bash
#
# Covers: FG-048
# CAPs:   build.shared-node-builder, build.from-node-source

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-048a]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/builder/node-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml \
         tests/smoke_node_version.sh \
         tests/smoke_corepack_wraps.sh \
         tests/smoke_syft_available.sh; do
  test -e "images/builder/node-trixie/${f}" \
    || fail "images/builder/node-trixie/${f} missing"
done
pass "all required files present"

say "2. builder/node-trixie builds"
bash scripts/build-image.sh builder/node-trixie >/dev/null
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' \
        images/builder/node-trixie/image.yaml)
docker image inspect "forge-local/builder/node-trixie:${tag}" >/dev/null \
  || fail "forge-local/builder/node-trixie:${tag} did not materialize after build"
pass "forge-local/builder/node-trixie:${tag} built"

say "3. Node toolchain + corepack + syft smokes"
for s in images/builder/node-trixie/tests/smoke_*.sh; do
  IMAGE_TAG="${tag}" bash "${s}" >/dev/null
done
pass "all smoke tests green"

say "4. image.yaml invariants: tag=0.1, depends_on=[node-slim-trixie] (FG-065 dogfood)"
[[ "$tag" == "0.1" ]] || fail "image.yaml tag = '${tag}' (want 0.1)"
grep -qE '^depends_on:' images/builder/node-trixie/image.yaml \
  || fail "image.yaml MUST have depends_on after FG-065 (dogfoods node-slim-trixie)"
grep -q 'node-slim-trixie' images/builder/node-trixie/image.yaml \
  || fail "image.yaml depends_on must list node-slim-trixie (FG-065 dogfood)"
pass "image.yaml correct"

echo
echo "FG-048a acceptance: all sections passed."
