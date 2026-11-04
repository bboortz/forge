#!/usr/bin/env bash
#
# Covers: FG-006
# CAPs:   image.nginx-serves-http, test.smoke-server-helper,
#         image.no-shell, image.zero-os-cves, test.size-budget
#
# Encodes the Gherkin scenarios from
# docs/stories/FG-006-nginx-scratch-trixie.md.
#
# Red before implementation: images/nginx-scratch-trixie/ doesn't exist,
# scripts/smoke-server.sh is absent. Green once Dockerfile + smoke suite
# land and the image builds + runs cleanly.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-006]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE_DIR="nginx-scratch-trixie"
IMAGE="forge-local/${IMAGE_DIR}:1.26"

# -----------------------------------------------------------------------------
# Section 1 — Image dir + reusable helper exist
# -----------------------------------------------------------------------------
say "1. images/${IMAGE_DIR}/ + scripts/smoke-server.sh in place"
test -d "images/${IMAGE_DIR}"              || { echo "  ✗ images/${IMAGE_DIR}/ missing" >&2; exit 1; }
test -f "images/${IMAGE_DIR}/Dockerfile"   || { echo "  ✗ Dockerfile missing"           >&2; exit 1; }
test -f "images/${IMAGE_DIR}/image.yaml"   || { echo "  ✗ image.yaml missing"            >&2; exit 1; }
test -f "images/${IMAGE_DIR}/nginx.conf"   || { echo "  ✗ nginx.conf missing"            >&2; exit 1; }
test -x "scripts/smoke-server.sh"          || { echo "  ✗ scripts/smoke-server.sh missing / not exec" >&2; exit 1; }
pass "image dir + helper script present"

# -----------------------------------------------------------------------------
# Section 2 — Build succeeds via the central build script
# -----------------------------------------------------------------------------
say "2. scripts/build-image.sh ${IMAGE_DIR} produces ${IMAGE}"
bash scripts/build-image.sh "${IMAGE_DIR}" >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

# -----------------------------------------------------------------------------
# Section 3 — nginx binary + config both validate
# -----------------------------------------------------------------------------
say "3. nginx -v and nginx -t pass"
bash "images/${IMAGE_DIR}/tests/smoke_binary_runs.sh"
bash "images/${IMAGE_DIR}/tests/smoke_config_validates.sh"

# -----------------------------------------------------------------------------
# Section 4 — smoke-server.sh works: nginx serves 200 on /
# -----------------------------------------------------------------------------
say "4. nginx serves 200 on / via scripts/smoke-server.sh"
bash "images/${IMAGE_DIR}/tests/smoke_serves_200.sh"

# -----------------------------------------------------------------------------
# Section 5 — no shell / zero OS CVEs / size budget
# -----------------------------------------------------------------------------
say "5. scratch hygiene"
bash "images/${IMAGE_DIR}/tests/smoke_no_shell.sh"
bash "images/${IMAGE_DIR}/tests/smoke_zero_os_cves.sh"
bash "images/${IMAGE_DIR}/tests/smoke_size.sh"

# -----------------------------------------------------------------------------
# Section 6 — Post-publish (opt-in)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "6. external cosign verify against the published digest"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "ghcr.io/bboortz/${IMAGE_DIR}:1.26" >/dev/null
  pass "cosign verify exits 0 for the published nginx-scratch-trixie:1.26"
else
  say "6. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-006 acceptance: all sections passed."
