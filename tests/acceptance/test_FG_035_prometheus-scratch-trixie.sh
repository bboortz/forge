#!/usr/bin/env bash
#
# Covers: FG-035
# CAPs:   image.prometheus-serves-metrics, image.no-shell, image.zero-os-cves,
#         image.ssl-cert-env, build.two-stage-scratch, test.size-budget,
#         build.scratch-baseline
#
# Validates FG-035: prometheus-scratch-trixie:2.53 — Debian trixie's
# prometheus 2.53.3 server FROM scratch; /-/healthy, /-/ready, SIGHUP
# reload, promtool via docker exec, outbound TLS (CA bundle via baseline).

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-035]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — image dir + required files present
# -----------------------------------------------------------------------------
say "1. images/prometheus-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         prometheus.yml \
         tests/smoke_binary_runs.sh tests/smoke_healthy_endpoint.sh \
         tests/smoke_ready_endpoint.sh tests/smoke_promtool_validates.sh \
         tests/smoke_sighup_reload.sh tests/smoke_outbound_tls.sh \
         tests/smoke_no_shell.sh tests/smoke_user_nonroot.sh \
         tests/smoke_size.sh tests/smoke_zero_os_cves.sh; do
  test -e "images/prometheus-scratch-trixie/${f}" \
    || fail "images/prometheus-scratch-trixie/${f} missing"
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build
# -----------------------------------------------------------------------------
say "2. prometheus-scratch-trixie:2.53 builds"
bash scripts/build-image.sh prometheus-scratch-trixie >/dev/null
docker image inspect forge-local/prometheus-scratch-trixie:2.53 >/dev/null
pass "forge-local/prometheus-scratch-trixie:2.53 built"

# -----------------------------------------------------------------------------
# Section 3 — per-image smoke suite
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_binary_runs.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_healthy_endpoint.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_ready_endpoint.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_promtool_validates.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_sighup_reload.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_outbound_tls.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_no_shell.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_user_nonroot.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_size.sh
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_zero_os_cves.sh
pass "all 10 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — image.yaml invariants
# -----------------------------------------------------------------------------
say "4. image.yaml: tag=2.53, depends_on=[scratch-base-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/prometheus-scratch-trixie/image.yaml)
[[ "${tag}" == "2.53" ]] || fail "image.yaml tag = '${tag}' (want 2.53)"
grep -qE '^[[:space:]]*-[[:space:]]*scratch-base-trixie' \
  images/prometheus-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list scratch-base-trixie"
pass "image.yaml correct"

echo
echo "FG-035 acceptance: all sections passed."
