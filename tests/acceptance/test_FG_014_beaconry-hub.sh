#!/usr/bin/env bash
#
# Covers: FG-014
# CAPs:   image.beaconry-hub, image.beaconry-hub-bundled-tools,
#         build.external-source, publish.external-image,
#         contracts.promises, contracts.expectations

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-014]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/beaconry-hub:0.1"

say "1. verify-image-dirs + verify-contracts green"
bash scripts/verify-image-dirs.sh >/dev/null
python3 scripts/verify-contracts.py >/dev/null
pass "verify-* passes"

say "2. build hub from upstream via ref: latest"
bash scripts/build-image.sh beaconry-hub >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

say "3. OCI labels carry upstream provenance"
revision=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
source=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')
[[ "${revision}" =~ ^[0-9a-f]{40}$ ]] || { echo "  ✗ revision not a sha: ${revision}" >&2; exit 1; }
[[ "${source}" == "https://github.com/bboortz/beaconry" ]] || { echo "  ✗ source: ${source}" >&2; exit 1; }
pass "revision=${revision} source=${source}"

say "4. hub smoke suite"
if [[ "${_FORGE_IN_CHECK:-0}" == "1" ]]; then
  pass "beaconry-hub smokes (skipped — covered by make check's test-images phase, FG-017 B)"
else
  bash scripts/test-images.sh beaconry-hub | grep -E '0 failure\(s\)' >/dev/null
  pass "all 7 hub smokes passed"
fi

if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "5. published digest + cosign verify"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "ghcr.io/bboortz/beaconry-hub:0.1" >/dev/null
  pass "cosign verify ghcr.io/bboortz/beaconry-hub:0.1"
else
  say "5. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-014 acceptance: all sections passed."
