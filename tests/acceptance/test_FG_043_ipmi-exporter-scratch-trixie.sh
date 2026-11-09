#!/usr/bin/env bash
#
# Covers: FG-043
# CAPs:   image.ipmi-exporter-serves-metrics (EXT),
#         image.ipmi-exporter-scratch-nonroot-exempt (NEW),
#         image.no-shell, image.zero-os-cves, image.hc-embedded,
#         build.two-stage-scratch, build.scratch-baseline,
#         test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-043]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — required files present
# -----------------------------------------------------------------------------
say "1. images/ipmi-exporter-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         ipmi-exporter.yml \
         tests/smoke_binary_runs.sh tests/smoke_freeipmi_tools.sh \
         tests/smoke_metrics_endpoint.sh tests/smoke_hc_healthcheck.sh \
         tests/smoke_no_shell.sh tests/smoke_user_root.sh \
         tests/smoke_size.sh tests/smoke_zero_os_cves.sh; do
  test -e "images/ipmi-exporter-scratch-trixie/${f}" \
    || fail "images/ipmi-exporter-scratch-trixie/${f} missing"
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build
# -----------------------------------------------------------------------------
say "2. ipmi-exporter-scratch-trixie:1.10 builds"
bash scripts/build-image.sh ipmi-exporter-scratch-trixie >/dev/null
docker image inspect forge-local/ipmi-exporter-scratch-trixie:1.10 >/dev/null
pass "forge-local/ipmi-exporter-scratch-trixie:1.10 built"

# -----------------------------------------------------------------------------
# Section 3 — per-image smoke suite (8 smokes)
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
for s in images/ipmi-exporter-scratch-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=1.10 bash "${s}"
done
pass "all 8 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — image.yaml: tag + depends_on scratch-base-trixie
# -----------------------------------------------------------------------------
say "4. image.yaml: tag=1.10, depends_on=[scratch-base-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' \
        images/ipmi-exporter-scratch-trixie/image.yaml)
[[ "${tag}" == "1.10" ]] || fail "image.yaml tag = '${tag}' (want 1.10)"
grep -qE '^[[:space:]]*-[[:space:]]*scratch-base-trixie' \
  images/ipmi-exporter-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list scratch-base-trixie"
pass "image.yaml correct"

# -----------------------------------------------------------------------------
# Section 5 — FG-037 slim variant still passes (coexistence)
# -----------------------------------------------------------------------------
say "5. FG-037 slim variant acceptance still green (coexistence)"
bash tests/acceptance/test_FG_037_ipmi-exporter-slim-trixie.sh >/dev/null
pass "test_FG_037_ipmi-exporter-slim-trixie.sh"

echo
echo "FG-043 acceptance: all sections passed."
