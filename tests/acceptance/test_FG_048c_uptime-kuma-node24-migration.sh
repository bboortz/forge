#!/usr/bin/env bash
#
# Covers: FG-048
# CAPs:   build.shared-node-builder, build.from-node-source,
#         image.uptime-kuma-serves-monitoring, image.has-shell

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-048c]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. uptime-kuma Dockerfile: builder FROMs builder/node-trixie"
dockerfile=images/uptime-kuma-slim-trixie/Dockerfile

grep -qE 'FROM \$\{BUILDER_NODE_REF\} AS builder' "$dockerfile" \
  || fail "uptime-kuma builder stage must FROM \${BUILDER_NODE_REF} (FG-048 migration)"
grep -qE '^ARG BUILDER_NODE_REF=ghcr\.io/bboortz/builder/node-trixie:(latest|[0-9.]+)' "$dockerfile" \
  || fail "uptime-kuma must declare ARG BUILDER_NODE_REF with a ghcr.io/bboortz/builder/node-trixie default"
pass "uptime-kuma builder migrated to builder/node-trixie"

say "2. uptime-kuma runtime FROMs the forge-rooted Node pre-builder (FG-061)"
# FG-048 originally set ARG NODE_BASE=node:24-trixie-slim and the runtime
# stage FROMed it directly. FG-061 introduced `node-slim-trixie` as the
# forge-rooted Node pre-builder and migrated uptime-kuma's runtime onto
# ${NODE_SLIM_REF}, so NODE_BASE is retired in favour of NODE_SLIM_REF
# (defaulting to ghcr.io/bboortz/node-slim-trixie:latest, which itself
# FROMs node:24-trixie-slim). The Node 24 LTS guarantee is still enforced
# by section 4 below (docker run node --version matches v24.*).
grep -qE '^ARG NODE_SLIM_REF=ghcr\.io/bboortz/pre-builder/node-slim-trixie:(latest|[0-9.]+)' "$dockerfile" \
  || fail "uptime-kuma must declare ARG NODE_SLIM_REF=ghcr.io/bboortz/pre-builder/node-slim-trixie:… (FG-061 migration)"
pass "NODE_SLIM_REF=ghcr.io/bboortz/pre-builder/node-slim-trixie:… (Node 24 LTS via forge pre-builder)"

say "3. uptime-kuma-slim-trixie builds via builder/node-trixie"
bash scripts/build-image.sh uptime-kuma-slim-trixie >/dev/null
docker image inspect forge-local/uptime-kuma-slim-trixie:latest >/dev/null \
  || fail "forge-local/uptime-kuma-slim-trixie:latest did not materialize"
pass "forge-local/uptime-kuma-slim-trixie:latest built"

say "4. Node runtime is v24.x"
set +e
out=$(docker run --rm --entrypoint=node \
      forge-local/uptime-kuma-slim-trixie:latest --version 2>&1)
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "node --version exited ${rc}: ${out}"
case "$out" in
  v24.*) pass "node version: ${out}" ;;
  *)     fail "node version must start with v24.*; got: ${out}" ;;
esac

say "5. FG-045 smoke suite still passes against Node 24 build"
# These are the FG-045 oracles for uptime-kuma. Must stay green across the
# Node 24 migration, otherwise we revert the runtime bump.
for s in images/uptime-kuma-slim-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=latest bash "${s}" >/dev/null
done
pass "all FG-045 smokes green against Node 24 build"

echo
echo "FG-048c acceptance: all sections passed."
