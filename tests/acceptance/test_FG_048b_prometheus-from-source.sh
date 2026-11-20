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
# FG-053: PROMETHEUS_VERSION is empty (FG-050 build.ref-latest-release
# pattern); resolved at build time via GitHub Releases API.
grep -qE '^ARG PROMETHEUS_VERSION=\s*$' "$dockerfile" \
  || fail "prometheus Dockerfile must have EMPTY ARG PROMETHEUS_VERSION= (FG-053 floating :latest per FG-050)"
grep -q 'api.github.com/repos/prometheus/prometheus/releases/latest' "$dockerfile" \
  || fail "prometheus Dockerfile must resolve upstream :latest via GitHub Releases API (FG-050)"
grep -q 'builtinassets' "$dockerfile" \
  || fail "prometheus Dockerfile must pass '-tags builtinassets' to embed UI into the binary"
pass "Dockerfile has ui-builder + go-builder + empty PROMETHEUS_VERSION resolve + builtinassets tag"

# -----------------------------------------------------------------------------
# §2. Image builds from source.
# -----------------------------------------------------------------------------

say "2. prometheus-scratch-trixie builds from source"
bash scripts/build-image.sh prometheus-scratch-trixie >/dev/null
docker image inspect forge-local/prometheus-scratch-trixie:latest >/dev/null \
  || fail "forge-local/prometheus-scratch-trixie:latest did not materialize"
pass "forge-local/prometheus-scratch-trixie:latest built"

# -----------------------------------------------------------------------------
# §3. Binary version banner reports go1.27+ stdlib + v2.53.5.
# -----------------------------------------------------------------------------

say "3. --version reports from-source build (floating :latest + go1.27+)"
set +e
out=$(docker run --rm --entrypoint=/usr/bin/prometheus \
      forge-local/prometheus-scratch-trixie:latest --version 2>&1)
rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "  ✗ prometheus --version exited ${rc}:" >&2; echo "$out" >&2; exit 1; }

# FG-053: accept any prometheus vX.Y.Z (floating :latest, resolved via API).
echo "$out" | grep -q "prometheus, version " \
  || fail "prometheus --version must report a version; got: $(echo "$out" | head -1)"
echo "$out" | grep -qE 'go version\s*:\s*go1\.(27|28|29|30|31)' \
  || fail "prometheus --version must report go1.27+ stdlib; got: $(echo "$out" | grep -i 'go version')"
pass "--version banner: $(echo "$out" | head -1)"

# -----------------------------------------------------------------------------
# §4. Zero Go-stdlib CRITICAL CVEs (eliminates Debian go1.24.x class).
# -----------------------------------------------------------------------------

say "4. Zero Debian-go1.24.x stdlib CRITICAL CVEs"
# shellcheck disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh
assert_image_go_stdlib_27plus "forge-local/prometheus-scratch-trixie:latest" /usr/bin/prometheus
assert_no_stdlib_critical    "forge-local/prometheus-scratch-trixie:latest"
pass "go1.27+ stdlib, zero CRITICAL Go-stdlib CVEs beyond waivers"

# -----------------------------------------------------------------------------
# §5. HTTP surface preserved (SPA + API endpoints).
# -----------------------------------------------------------------------------

say "5. HTTP surface preserved: SPA + /-/healthy + /-/ready + homelab-compat"
# scripts/smoke-server.sh boots the container, probes endpoints, cleans up.
IMAGE_TAG=latest bash images/prometheus-scratch-trixie/tests/smoke_web_ui.sh >/dev/null
IMAGE_TAG=latest bash images/prometheus-scratch-trixie/tests/smoke_healthy_endpoint.sh >/dev/null
IMAGE_TAG=latest bash images/prometheus-scratch-trixie/tests/smoke_ready_endpoint.sh >/dev/null
IMAGE_TAG=latest bash images/prometheus-scratch-trixie/tests/smoke_console_files.sh >/dev/null
IMAGE_TAG=latest bash images/prometheus-scratch-trixie/tests/smoke_lifecycle_reload.sh >/dev/null
pass "all HTTP endpoints respond — embedded UI + /-/healthy + /-/ready + console templates + lifecycle reload"

# -----------------------------------------------------------------------------
# §6. Per-image smoke suite fully green.
# -----------------------------------------------------------------------------

say "6. prometheus-scratch-trixie full smoke suite"
for s in images/prometheus-scratch-trixie/tests/smoke_*.sh; do
  IMAGE_TAG=latest bash "${s}" >/dev/null
done
pass "all smokes green"

# -----------------------------------------------------------------------------
# §7. image.yaml invariants.
# -----------------------------------------------------------------------------

say "7. image.yaml: tag=latest (FG-053 floating), depends_on=[base/scratch-trixie]"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' \
        images/prometheus-scratch-trixie/image.yaml)
[[ "$tag" == "latest" ]] || fail "image.yaml tag = '${tag}' (want latest per FG-053)"
grep -qE '^[[:space:]]*-[[:space:]]*base/scratch-trixie' \
  images/prometheus-scratch-trixie/image.yaml \
  || fail "image.yaml: depends_on must list base/scratch-trixie"
pass "image.yaml correct"

echo
echo "FG-048b acceptance: all sections passed."
