#!/usr/bin/env bash
#
# Covers: FG-036
# CAPs:   image.alertmanager-routes-alerts, image.no-shell, image.zero-os-cves,
#         image.ssl-cert-env, build.two-stage-scratch, test.size-budget,
#         build.scratch-baseline

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-036]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. images/alertmanager-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         alertmanager.yml \
         tests/smoke_binary_runs.sh tests/smoke_healthy_endpoint.sh \
         tests/smoke_ready_endpoint.sh tests/smoke_amtool_validates.sh \
         tests/smoke_ssl_cert_env.sh tests/smoke_hc_healthcheck.sh \
         tests/smoke_no_shell.sh tests/smoke_user_nonroot.sh \
         tests/smoke_size.sh tests/smoke_zero_os_cves.sh; do
  test -e "images/alertmanager-scratch-trixie/${f}" \
    || fail "images/alertmanager-scratch-trixie/${f} missing"
done
pass "all required files present"

say "2. alertmanager-scratch-trixie:0.28 builds"
bash scripts/build-image.sh alertmanager-scratch-trixie >/dev/null
docker image inspect forge-local/alertmanager-scratch-trixie:0.28 >/dev/null
pass "forge-local/alertmanager-scratch-trixie:0.28 built"

say "3. per-image smoke suite"
for s in images/alertmanager-scratch-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=0.28 bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=0.28, depends_on=[scratch-base-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/alertmanager-scratch-trixie/image.yaml)
[[ "${tag}" == "0.28" ]] || fail "image.yaml tag = '${tag}' (want 0.28)"
grep -qE '^[[:space:]]*-[[:space:]]*scratch-base-trixie' \
  images/alertmanager-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list scratch-base-trixie"
pass "image.yaml correct"

echo
echo "FG-036 acceptance: all sections passed."
