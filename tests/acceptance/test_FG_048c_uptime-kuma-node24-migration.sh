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

say "1. uptime-kuma Dockerfile: builder FROMs forge-builder-node-trixie"
dockerfile=images/uptime-kuma-slim-trixie/Dockerfile

grep -qE 'FROM \$\{FORGE_BUILDER_NODE_REF\} AS builder' "$dockerfile" \
  || fail "uptime-kuma builder stage must FROM \${FORGE_BUILDER_NODE_REF} (FG-048 migration)"
grep -qE '^ARG FORGE_BUILDER_NODE_REF=ghcr\.io/bboortz/forge-builder-node-trixie:(latest|[0-9.]+)' "$dockerfile" \
  || fail "uptime-kuma must declare ARG FORGE_BUILDER_NODE_REF with a ghcr.io/bboortz/forge-builder-node-trixie default"
pass "uptime-kuma builder migrated to forge-builder-node-trixie"

say "2. uptime-kuma runtime base bumped to node:24-trixie-slim"
grep -qE '^ARG NODE_BASE=node:24-trixie-slim' "$dockerfile" \
  || fail "uptime-kuma must set NODE_BASE=node:24-trixie-slim (FG-048 runtime bump)"
pass "NODE_BASE=node:24-trixie-slim"

say "3. uptime-kuma-slim-trixie builds via forge-builder-node-trixie"
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
