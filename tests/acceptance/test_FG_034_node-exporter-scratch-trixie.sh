#!/usr/bin/env bash
#
# Covers: FG-034
# CAPs:   image.node-exporter-serves-metrics, image.no-shell, image.zero-os-cves,
#         build.two-stage-scratch, test.size-budget, build.scratch-baseline
#
# Validates FG-034: node-exporter-scratch-trixie:1.9 — Debian trixie's
# prometheus-node-exporter 1.9.0 running FROM scratch, scraping /metrics
# via :9100 without a shell.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-034]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — image dir + required files present
# -----------------------------------------------------------------------------
say "1. images/node-exporter-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         tests/smoke_binary_runs.sh tests/smoke_metrics_endpoint.sh \
         tests/smoke_hc_healthcheck.sh \
         tests/smoke_no_shell.sh tests/smoke_user_nonroot.sh \
         tests/smoke_size.sh tests/smoke_zero_os_cves.sh; do
  test -e "images/node-exporter-scratch-trixie/${f}" \
    || fail "images/node-exporter-scratch-trixie/${f} missing"
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build
# -----------------------------------------------------------------------------
say "2. node-exporter-scratch-trixie:1.9 builds"
bash scripts/build-image.sh node-exporter-scratch-trixie >/dev/null
docker image inspect forge-local/node-exporter-scratch-trixie:1.9 >/dev/null
pass "forge-local/node-exporter-scratch-trixie:1.9 built"

# -----------------------------------------------------------------------------
# Section 3 — per-image smoke suite
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_binary_runs.sh
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_metrics_endpoint.sh
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_hc_healthcheck.sh
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_no_shell.sh
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_user_nonroot.sh
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_size.sh
IMAGE_TAG=1.9 bash images/node-exporter-scratch-trixie/tests/smoke_zero_os_cves.sh
pass "all 7 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — image.yaml invariants
# -----------------------------------------------------------------------------
say "4. image.yaml: tag=1.9, depends_on=[scratch-base-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/node-exporter-scratch-trixie/image.yaml)
[[ "${tag}" == "1.9" ]] || fail "image.yaml tag = '${tag}' (want 1.9)"
grep -qE '^[[:space:]]*-[[:space:]]*scratch-base-trixie' \
  images/node-exporter-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list scratch-base-trixie"
pass "image.yaml correct (tag=1.9, depends_on=scratch-base-trixie)"

echo
echo "FG-034 acceptance: all sections passed."
