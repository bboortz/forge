#!/usr/bin/env bash
#
# Covers: FG-037
# CAPs:   image.ipmi-exporter-serves-metrics, image.has-shell,
#         scan.regression-gate, test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-037]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/ipmi-exporter-slim-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         ipmi-exporter.yml \
         tests/smoke_binary_runs.sh tests/smoke_metrics_endpoint.sh \
         tests/smoke_freeipmi_tools.sh tests/smoke_hc_healthcheck.sh \
         tests/smoke_has_shell.sh tests/smoke_size.sh; do
  test -e "images/ipmi-exporter-slim-trixie/${f}" \
    || fail "images/ipmi-exporter-slim-trixie/${f} missing"
done
# Slim images do NOT ship EXPECTATIONS.yaml (no scratch-base dependency).
test ! -e images/ipmi-exporter-slim-trixie/EXPECTATIONS.yaml \
  || fail "images/ipmi-exporter-slim-trixie/EXPECTATIONS.yaml should not exist (slim, not scratch)"
pass "all required files present (slim contract)"

say "2. ipmi-exporter-slim-trixie:1.10 builds"
bash scripts/build-image.sh ipmi-exporter-slim-trixie >/dev/null
docker image inspect forge-local/ipmi-exporter-slim-trixie:1.10 >/dev/null
pass "forge-local/ipmi-exporter-slim-trixie:1.10 built"

say "3. per-image smoke suite"
for s in images/ipmi-exporter-slim-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=1.10 bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=1.10, NO depends_on (slim variant)"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/ipmi-exporter-slim-trixie/image.yaml)
[[ "${tag}" == "1.10" ]] || fail "image.yaml tag = '${tag}' (want 1.10)"
if grep -qE '^depends_on:' images/ipmi-exporter-slim-trixie/image.yaml; then
  fail "image.yaml should NOT have depends_on (slim variant, not scratch derivative)"
fi
pass "image.yaml correct (tag=1.10, no depends_on)"

echo
echo "FG-037 acceptance: all sections passed."
