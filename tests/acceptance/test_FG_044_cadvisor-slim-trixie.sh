#!/usr/bin/env bash
#
# Covers: FG-044
# CAPs:   image.cadvisor-serves-metrics, build.from-go-source,
#         image.has-shell, scan.regression-gate, test.size-budget,
#         image.hc-embedded

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-044]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/cadvisor-slim-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         tests/smoke_binary_runs.sh tests/smoke_static_binary.sh \
         tests/smoke_healthz.sh tests/smoke_metrics_endpoint.sh \
         tests/smoke_hc_healthcheck.sh tests/smoke_has_shell.sh \
         tests/smoke_size.sh; do
  test -e "images/cadvisor-slim-trixie/${f}" \
    || fail "images/cadvisor-slim-trixie/${f} missing"
done
# Slim images do NOT ship EXPECTATIONS.yaml (no scratch-base dependency).
test ! -e images/cadvisor-slim-trixie/EXPECTATIONS.yaml \
  || fail "images/cadvisor-slim-trixie/EXPECTATIONS.yaml should not exist (slim, not scratch)"
pass "all required files present (slim contract)"

say "2. cadvisor-slim-trixie:0.60.6 builds from Go source"
bash scripts/build-image.sh cadvisor-slim-trixie >/dev/null
docker image inspect forge-local/cadvisor-slim-trixie:0.60.6 >/dev/null
pass "forge-local/cadvisor-slim-trixie:0.60.6 built"

say "3. per-image smoke suite"
for s in images/cadvisor-slim-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=0.60.6 bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=0.60.6, NO depends_on (slim variant)"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/cadvisor-slim-trixie/image.yaml)
[[ "${tag}" == "0.60.6" ]] || fail "image.yaml tag = '${tag}' (want 0.60.6)"
if grep -qE '^depends_on:' images/cadvisor-slim-trixie/image.yaml; then
  fail "image.yaml should NOT have depends_on (slim variant, not scratch derivative)"
fi
pass "image.yaml correct (tag=0.60.6, no depends_on)"

echo
echo "FG-044 acceptance: all sections passed."
