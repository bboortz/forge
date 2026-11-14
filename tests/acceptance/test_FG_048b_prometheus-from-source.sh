#!/usr/bin/env bash
#
# Covers: FG-048
# CAPs:   build.shared-node-builder, build.shared-go-builder,
#         build.from-node-and-go-source, image.prometheus-serves-metrics,
#         scan.regression-gate, test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-048b]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# §1. Dockerfile is the new dual-builder shape (Node UI + Go binary).
# -----------------------------------------------------------------------------

say "1. prometheus Dockerfile is the new dual-builder shape"
dockerfile=images/prometheus-scratch-trixie/Dockerfile

grep -qE 'FROM \$\{FORGE_BUILDER_NODE_REF\} AS ui-builder' "$dockerfile" \
  || fail "prometheus Dockerfile missing 'FROM \${FORGE_BUILDER_NODE_REF} AS ui-builder' stage"
grep -qE 'FROM \$\{FORGE_BUILDER_GO_REF\} AS (go-builder|builder)' "$dockerfile" \
  || fail "prometheus Dockerfile missing a 'FROM \${FORGE_BUILDER_GO_REF}' stage"
grep -qE '^ARG PROMETHEUS_VERSION=v2\.53\.5' "$dockerfile" \
  || fail "prometheus Dockerfile must pin PROMETHEUS_VERSION=v2.53.5 (FG-048 scope — v2.53 LTS)"
grep -q 'builtinassets' "$dockerfile" \
  || fail "prometheus Dockerfile must pass '-tags builtinassets' to embed UI into the binary"
pass "Dockerfile has ui-builder + go-builder + PROMETHEUS_VERSION=v2.53.5 + builtinassets tag"

# -----------------------------------------------------------------------------
# §2. Image builds from source.
# -----------------------------------------------------------------------------

say "2. prometheus-scratch-trixie builds from source"
bash scripts/build-image.sh prometheus-scratch-trixie >/dev/null
docker image inspect forge-local/prometheus-scratch-trixie:2.53 >/dev/null \
  || fail "forge-local/prometheus-scratch-trixie:2.53 did not materialize"
pass "forge-local/prometheus-scratch-trixie:2.53 built"

# -----------------------------------------------------------------------------
# §3. Binary version banner reports go1.27+ stdlib + v2.53.5.
# -----------------------------------------------------------------------------

say "3. --version reports from-source build (v2.53.5 + go1.27+)"
set +e
out=$(docker run --rm --entrypoint=/usr/bin/prometheus \
      forge-local/prometheus-scratch-trixie:2.53 --version 2>&1)
rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "  ✗ prometheus --version exited ${rc}:" >&2; echo "$out" >&2; exit 1; }

echo "$out" | grep -q "prometheus, version 2.53.5" \
  || fail "prometheus --version must report 2.53.5; got: $(echo "$out" | head -1)"
echo "$out" | grep -qE 'go version\s*:\s*go1\.(27|28|29|30|31)' \
  || fail "prometheus --version must report go1.27+ stdlib; got: $(echo "$out" | grep -i 'go version')"
pass "--version banner: $(echo "$out" | head -1)"

# -----------------------------------------------------------------------------
# §4. Zero Go-stdlib CRITICAL CVEs (eliminates Debian go1.24.x class).
# -----------------------------------------------------------------------------

say "4. Zero Debian-go1.24.x stdlib CRITICAL CVEs"
# shellcheck disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh
assert_image_go_stdlib_27plus "forge-local/prometheus-scratch-trixie:2.53" /usr/bin/prometheus
assert_no_stdlib_critical    "forge-local/prometheus-scratch-trixie:2.53"
pass "go1.27+ stdlib, zero CRITICAL Go-stdlib CVEs beyond waivers"

# -----------------------------------------------------------------------------
# §5. HTTP surface preserved (SPA + API endpoints).
# -----------------------------------------------------------------------------

say "5. HTTP surface preserved: SPA + /-/healthy + /-/ready + homelab-compat"
# scripts/smoke-server.sh boots the container, probes endpoints, cleans up.
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_web_ui.sh >/dev/null
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_healthy_endpoint.sh >/dev/null
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_ready_endpoint.sh >/dev/null
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_console_files.sh >/dev/null
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_lifecycle_reload.sh >/dev/null
pass "all HTTP endpoints respond — embedded UI + /-/healthy + /-/ready + console templates + lifecycle reload"

# -----------------------------------------------------------------------------
# §6. Per-image smoke suite fully green.
# -----------------------------------------------------------------------------

say "6. prometheus-scratch-trixie full smoke suite"
for s in images/prometheus-scratch-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=2.53 bash "${s}" >/dev/null
done
pass "all smokes green"

# -----------------------------------------------------------------------------
# §7. image.yaml invariants.
# -----------------------------------------------------------------------------

say "7. image.yaml: tag=2.53, depends_on=[scratch-base-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' \
        images/prometheus-scratch-trixie/image.yaml)
[[ "$tag" == "2.53" ]] || fail "image.yaml tag = '${tag}' (want 2.53)"
grep -qE '^[[:space:]]*-[[:space:]]*scratch-base-trixie' \
  images/prometheus-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list scratch-base-trixie"
pass "image.yaml correct"

echo
echo "FG-048b acceptance: all sections passed."
