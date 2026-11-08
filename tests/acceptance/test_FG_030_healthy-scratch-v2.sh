#!/usr/bin/env bash
#
# Covers: FG-030
# CAPs:   image.healthy-sidecar, image.no-shell, scan.sbom-embed,
#         test.size-budget
#
# Validates FG-030: healthy-scratch-trixie:2 — hc-based minimal sidecar
# replacing FG-029's wget approach. Image ≤ 5 MB. GnuTLS stack gone.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-030]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — image dir + required files
# -----------------------------------------------------------------------------
say "1. images/healthy-scratch-trixie/ has required v2 layout"
for f in Dockerfile image.yaml PROMISES.yaml scan-baseline.json \
         tests/smoke_binary_runs.sh tests/smoke_cmd_sleeps.sh \
         tests/smoke_sidecar_healthcheck.sh tests/smoke_contents.sh \
         tests/smoke_no_shell.sh tests/smoke_size.sh; do
  test -e "images/healthy-scratch-trixie/${f}" \
    || { echo "  ✗ images/healthy-scratch-trixie/${f} missing" >&2; exit 1; }
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build (requires ghcr.io/bboortz/hc:0.1.0 OR forge-local/hc:0.1.0)
# -----------------------------------------------------------------------------
say "2. healthy-scratch-trixie:2 builds"
# Assume local hc image is present (set up for testing before HC-005 lands).
# CI will build against ghcr.io/bboortz/hc:0.1.0 once HC-005 has published.
if ! docker image inspect forge-local/healthy-scratch-trixie:2 >/dev/null 2>&1; then
  if docker image inspect forge-local/hc:0.1.0 >/dev/null 2>&1; then
    docker build \
      --build-arg HC_REF=forge-local/hc:0.1.0 \
      --build-arg FORGE_BUILDER_REF=forge-local/forge-builder-trixie:0.1 \
      --build-arg GIT_SHA="$(git rev-parse HEAD)" \
      --build-arg BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      -t forge-local/healthy-scratch-trixie:2 \
      images/healthy-scratch-trixie/ >/dev/null
  else
    bash scripts/build-image.sh healthy-scratch-trixie >/dev/null
  fi
fi
docker image inspect forge-local/healthy-scratch-trixie:2 >/dev/null
pass "forge-local/healthy-scratch-trixie:2 built"

# -----------------------------------------------------------------------------
# Section 3 — per-image smoke suite
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
IMAGE_TAG=2 bash images/healthy-scratch-trixie/tests/smoke_binary_runs.sh
IMAGE_TAG=2 bash images/healthy-scratch-trixie/tests/smoke_cmd_sleeps.sh
IMAGE_TAG=2 bash images/healthy-scratch-trixie/tests/smoke_contents.sh
IMAGE_TAG=2 bash images/healthy-scratch-trixie/tests/smoke_no_shell.sh
IMAGE_TAG=2 bash images/healthy-scratch-trixie/tests/smoke_sidecar_healthcheck.sh
IMAGE_TAG=2 bash images/healthy-scratch-trixie/tests/smoke_size.sh
pass "all 6 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — image.yaml declares correct tag + no scratch-base dep
# -----------------------------------------------------------------------------
say "4. image.yaml: tag=2, no depends_on (raw FROM scratch)"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' images/healthy-scratch-trixie/image.yaml)
[[ "${tag}" == "2" ]] || { echo "  ✗ image.yaml tag = '${tag}' (want 2)" >&2; exit 1; }
if grep -qE '^depends_on:' images/healthy-scratch-trixie/image.yaml; then
  echo "  ✗ image.yaml has depends_on — FG-030 is raw FROM scratch" >&2
  exit 1
fi
pass "image.yaml correct (tag=2, no depends_on)"

echo
echo "FG-030 acceptance: all sections passed."
