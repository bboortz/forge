#!/usr/bin/env bash
#
# Covers: FG-015
# CAPs:   image.beaconry-telegram-mock, build.external-source,
#         publish.external-image, contracts.promises

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-015]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/beaconry-telegram-mock:0.1"

say "1. verify-image-dirs + verify-contracts green (no depends_on → no EXPECTATIONS required)"
bash scripts/verify-image-dirs.sh >/dev/null
python3 scripts/verify-contracts.py >/dev/null
pass "verify-* passes with no-deps image"

say "2. build via ref: latest"
bash scripts/build-image.sh beaconry-telegram-mock >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

say "3. OCI labels pin upstream provenance"
revision=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
source=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')
[[ "${revision}" =~ ^[0-9a-f]{40}$ ]] || { echo "  ✗ revision not a sha: ${revision}" >&2; exit 1; }
[[ "${source}" == "https://github.com/bboortz/beaconry" ]] || { echo "  ✗ source: ${source}" >&2; exit 1; }
pass "revision=${revision} source=${source}"

say "4. mock smoke suite"
bash scripts/test-images.sh beaconry-telegram-mock | grep -E '0 failure\(s\)' >/dev/null
pass "all 3 mock smokes passed"

if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "5. cosign verify published digest"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "ghcr.io/bboortz/beaconry-telegram-mock:0.1" >/dev/null
  pass "cosign verify ghcr.io/bboortz/beaconry-telegram-mock:0.1"
else
  say "5. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-015 acceptance: all sections passed."
