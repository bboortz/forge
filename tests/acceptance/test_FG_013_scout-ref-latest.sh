#!/usr/bin/env bash
#
# Covers: FG-013
# CAPs:   build.external-source, publish.external-image, image.beaconry-scout
#
# Proves that source.ref: "latest" resolves to the current beaconry main HEAD
# and bakes the resolved sha (NOT the literal string "latest") into
# org.opencontainers.image.revision.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-013]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/beaconry-scout:0.1"

# -----------------------------------------------------------------------------
# Section 1 — image.yaml declares ref: latest
# -----------------------------------------------------------------------------
say "1. image.yaml declares source.ref: latest"
grep -qE '^\s*ref:\s*"?latest"?' images/beaconry-scout/image.yaml \
  || { echo "✗ image.yaml source.ref is not 'latest'" >&2; exit 1; }
pass "source.ref: latest"

# -----------------------------------------------------------------------------
# Section 2 — build resolves latest → concrete sha
# -----------------------------------------------------------------------------
say "2. build resolves latest → concrete upstream sha"
bash scripts/build-image.sh beaconry-scout >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

revision=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
if [[ "${revision}" == "latest" ]]; then
  echo "  ✗ label is the literal string 'latest' — ref was NOT resolved" >&2
  exit 1
fi
if [[ ! "${revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "  ✗ label '${revision}' is not a 40-char sha" >&2
  exit 1
fi
pass "org.opencontainers.image.revision = ${revision} (resolved sha)"

# -----------------------------------------------------------------------------
# Section 3 — resolved sha matches current upstream main HEAD
# -----------------------------------------------------------------------------
say "3. resolved sha matches upstream main HEAD"
upstream_head=$(git ls-remote https://github.com/bboortz/beaconry HEAD | awk '{print $1}')
if [[ "${revision}" != "${upstream_head}" ]]; then
  echo "  ✗ image revision ${revision} != upstream HEAD ${upstream_head}" >&2
  exit 1
fi
pass "image revision == upstream main HEAD (${upstream_head})"

# -----------------------------------------------------------------------------
# Section 4 — all smokes still pass against the latest-resolved build
# -----------------------------------------------------------------------------
say "4. beaconry-scout smokes still pass"
bash scripts/test-images.sh beaconry-scout | grep -E '0 failure\(s\)' >/dev/null
pass "all 5 beaconry-scout smokes passed"

echo
echo "FG-013 acceptance: all sections passed."
