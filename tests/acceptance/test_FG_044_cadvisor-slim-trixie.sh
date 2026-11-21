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
# FG-077: slim runtimes now declare base/* parent via depends_on; that
# requires EXPECTATIONS.yaml (verify-contracts rule).
test -e images/cadvisor-slim-trixie/EXPECTATIONS.yaml \
  || fail "images/cadvisor-slim-trixie/EXPECTATIONS.yaml must exist post-FG-077 (declares base/debian-slim-trixie expectations)"
pass "all required files present (slim contract post-FG-077)"

say "2. cadvisor-slim-trixie:latest builds from Go source"
bash scripts/build-image.sh cadvisor-slim-trixie >/dev/null
docker image inspect forge-local/cadvisor-slim-trixie:latest >/dev/null
pass "forge-local/cadvisor-slim-trixie:latest built"

say "3. per-image smoke suite"
for s in images/cadvisor-slim-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=latest bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=latest (FG-050 flipped to :latest), depends_on base/* (FG-077)"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/cadvisor-slim-trixie/image.yaml)
[[ "${tag}" == "latest" ]] || fail "image.yaml tag = '${tag}' (want latest)"
if ! grep -qE '^depends_on:' images/cadvisor-slim-trixie/image.yaml; then
  fail "image.yaml must declare depends_on post-FG-077 (slim consumer FROMs base/*)"
fi
pass "image.yaml correct (tag=latest, depends_on base/*)"

echo
echo "FG-044 acceptance: all sections passed."
