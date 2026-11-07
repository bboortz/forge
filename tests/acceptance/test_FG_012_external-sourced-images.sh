#!/usr/bin/env bash
#
# Covers: FG-012
# CAPs:   build.external-source, publish.external-image,
#         image.beaconry-scout, image.beaconry-scout-bundled-syft,
#         contracts.promises, contracts.expectations
#
# Validates (1) the externally-sourced images mechanism (source: block,
# verify-image-dirs lint, build-image.sh clone-then-build, OCI labels) and
# (2) the first consumer — beaconry-scout at a pinned upstream sha.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-012]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/beaconry-scout:0.1"
# FG-012 originally pinned scout to a specific sha. FG-013 switched scout to
# ref: latest, so section 4 now asserts the mechanism (label is a 40-char
# sha, NOT the literal "latest") rather than a fixed value. This keeps
# test_FG_012 stable across ref-schema changes.

# -----------------------------------------------------------------------------
# Section 1 — current graph is consistent (verify-image-dirs + verify-contracts)
# -----------------------------------------------------------------------------
say "1. verify-image-dirs + verify-contracts are green on the current graph"
bash scripts/verify-image-dirs.sh >/dev/null
pass "verify-image-dirs: ok"
python3 scripts/verify-contracts.py >/dev/null
pass "verify-contracts: ok"

# -----------------------------------------------------------------------------
# Section 2 — source + local Dockerfile mutually exclusive
# -----------------------------------------------------------------------------
say "2. source: + local Dockerfile is a verify-image-dirs violation"
touch images/beaconry-scout/Dockerfile
set +e
bash scripts/verify-image-dirs.sh >/tmp/vid.out 2>&1
rc=$?
set -e
rm -f images/beaconry-scout/Dockerfile
if [[ ${rc} -ne 0 ]] && grep -q 'mutually exclusive' /tmp/vid.out; then
  pass "verify-image-dirs fails with the mutual-exclusion message"
else
  echo "  ✗ expected failure not raised (rc=${rc})" >&2
  cat /tmp/vid.out >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Section 3 — source with empty ref is rejected
# -----------------------------------------------------------------------------
say "3. source with empty ref is a verify-image-dirs violation"
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
cp images/beaconry-scout/image.yaml "${tmp}/image.yaml.bak"
python3 - images/beaconry-scout/image.yaml <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text()
t = re.sub(r'(^\s*ref:\s*).*$', r'\1""', t, flags=re.MULTILINE)
p.write_text(t)
PY
set +e
bash scripts/verify-image-dirs.sh >/tmp/vid2.out 2>&1
rc=$?
set -e
cp "${tmp}/image.yaml.bak" images/beaconry-scout/image.yaml
if [[ ${rc} -ne 0 ]] && grep -q 'source.ref is empty' /tmp/vid2.out; then
  pass "verify-image-dirs fails with the empty-ref message"
else
  echo "  ✗ empty-ref not caught (rc=${rc})" >&2
  cat /tmp/vid2.out >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Section 4 — build at pinned sha; OCI labels carry upstream provenance
# -----------------------------------------------------------------------------
say "4. external build at pinned sha + OCI labels"
bash scripts/build-image.sh beaconry-scout >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built from upstream clone"

revision=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
source=$(docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')
if [[ ! "${revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "  ✗ .Config.Labels.org.opencontainers.image.revision = ${revision}, expected a 40-char sha" >&2
  exit 1
fi
if [[ "${source}" != "https://github.com/bboortz/beaconry" ]]; then
  echo "  ✗ .Config.Labels.org.opencontainers.image.source = ${source}" >&2
  exit 1
fi
pass "image labels: revision=${revision} (sha) + source=upstream repo"

# -----------------------------------------------------------------------------
# Section 5 — beaconry-scout smoke suite passes
# -----------------------------------------------------------------------------
say "5. beaconry-scout smoke suite"
if [[ "${_FORGE_IN_CHECK:-0}" == "1" ]]; then
  pass "beaconry-scout smokes (skipped — covered by make check's test-images phase, FG-017 B)"
else
  bash scripts/test-images.sh beaconry-scout | grep -E '0 failure\(s\)' >/dev/null
  pass "all 5 beaconry-scout smokes passed"
fi

# -----------------------------------------------------------------------------
# Section 6 — Post-publish (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "6. published digest exists + cosign verify green"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "ghcr.io/bboortz/beaconry-scout:0.1" >/dev/null
  pass "cosign verify ghcr.io/bboortz/beaconry-scout:0.1"
else
  say "6. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-012 acceptance: all sections passed."
