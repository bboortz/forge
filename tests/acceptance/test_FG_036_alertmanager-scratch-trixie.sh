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

say "2. alertmanager-scratch-trixie:latest builds"
bash scripts/build-image.sh alertmanager-scratch-trixie >/dev/null
docker image inspect forge-local/alertmanager-scratch-trixie:latest >/dev/null
pass "forge-local/alertmanager-scratch-trixie:latest built"

say "3. per-image smoke suite"
for s in images/alertmanager-scratch-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=latest bash "${s}"
done
pass "all smoke tests green"

say "4. image.yaml: tag=latest, depends_on=[base/scratch-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/alertmanager-scratch-trixie/image.yaml)
[[ "${tag}" == "latest" ]] || fail "image.yaml tag = '${tag}' (want latest)"
grep -qE '^[[:space:]]*-[[:space:]]*base/scratch-trixie' \
  images/alertmanager-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list base/scratch-trixie"
pass "image.yaml correct"

echo
echo "FG-036 acceptance: all sections passed."
