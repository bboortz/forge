#!/usr/bin/env bash
#
# Covers: FG-045
# CAPs:   image.uptime-kuma-serves-monitoring, image.uptime-kuma-no-chromium,
#         image.uptime-kuma-nonroot, build.from-node-source,
#         image.has-shell, image.hc-embedded, scan.regression-gate,
#         test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-045]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/uptime-kuma-slim-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         tests/smoke_serves_200.sh tests/smoke_node_version.sh \
         tests/smoke_no_chromium.sh tests/smoke_user_node.sh \
         tests/smoke_hc_healthcheck.sh tests/smoke_has_shell.sh \
         tests/smoke_size.sh; do
  test -e "images/uptime-kuma-slim-trixie/${f}" \
    || fail "images/uptime-kuma-slim-trixie/${f} missing"
done
# Slim images do NOT ship EXPECTATIONS.yaml (no scratch-base dependency).
test ! -e images/uptime-kuma-slim-trixie/EXPECTATIONS.yaml \
  || fail "images/uptime-kuma-slim-trixie/EXPECTATIONS.yaml should not exist (slim, not scratch)"
pass "all required files present (slim contract)"

say "2. uptime-kuma-slim-trixie:latest builds from Node source"
bash scripts/build-image.sh uptime-kuma-slim-trixie >/dev/null
docker image inspect forge-local/uptime-kuma-slim-trixie:latest >/dev/null
pass "forge-local/uptime-kuma-slim-trixie:latest built"

say "3. per-image smoke suite"
for s in images/uptime-kuma-slim-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=latest bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=latest, NO depends_on (slim variant)"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/uptime-kuma-slim-trixie/image.yaml)
[[ "${tag}" == "latest" ]] || fail "image.yaml tag = '${tag}' (want latest)"
if grep -qE '^depends_on:' images/uptime-kuma-slim-trixie/image.yaml; then
  fail "image.yaml should NOT have depends_on (slim variant, not scratch derivative)"
fi
pass "image.yaml correct (tag=latest, no depends_on)"

echo
echo "FG-045 acceptance: all sections passed."
