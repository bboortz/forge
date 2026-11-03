#!/usr/bin/env bash
#
# Covers: FG-001
# CAPs:   build.pr-ci, build.daily-publish, sbom.cyclonedx-attest,
#         scan.grype-attest, sign.cosign-keyless-oidc, sign.cosign-local-dev,
#         verify.consumer-cmd, publish.ghcr-public-pull
#
# Encodes the Gherkin scenarios from docs/stories/FG-001-python-slim-pipeline.md.
# Red before implementation (no Makefile → section 1 fails); green when
# `make build / scan / sign-local / verify` all succeed locally.
#
# PUBLISHED=1 enables the sections that require a published digest
# (external cosign verify, GHCR anonymous pull). Default: skip them.
#
# Exit codes: 0 = pass, non-zero = fail. Each section echoes a pass line.

set -euo pipefail

IMAGE_DIR="python-slim-trixie"
IMAGE_REPO="python-slim-trixie"          # FG-004: repo name == dir name
IMAGE_TAG="3.13"                         # FG-004: version only
IMAGE_LOCAL="forge-local/${IMAGE_REPO}:${IMAGE_TAG}"
IMAGE_PUBLISHED="ghcr.io/bboortz/${IMAGE_REPO}:${IMAGE_TAG}"
BUILD_DIR="build"
SBOM="${BUILD_DIR}/${IMAGE_REPO}-${IMAGE_TAG}.sbom.json"
GRYPE="${BUILD_DIR}/${IMAGE_REPO}-${IMAGE_TAG}.grype.json"

cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-001]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — Scenario: Image builds locally
# -----------------------------------------------------------------------------
say "1. make build produces a local image"
make build IMAGE_DIR="$IMAGE_DIR"
docker image inspect "$IMAGE_LOCAL" >/dev/null
pass "local image $IMAGE_LOCAL exists"
test "$(docker run --rm "$IMAGE_LOCAL" python3 -c "print('ok')")" = "ok"
pass "python3 -c \"print('ok')\" prints ok"

# -----------------------------------------------------------------------------
# Section 2 — Scenario: SBOM is produced in CycloneDX format
# -----------------------------------------------------------------------------
say "2. syft SBOM is CycloneDX"
make scan IMAGE_DIR="$IMAGE_DIR"
test -f "$SBOM"
jq -e '.bomFormat == "CycloneDX"' "$SBOM" >/dev/null
pass "$SBOM has bomFormat == CycloneDX"

# -----------------------------------------------------------------------------
# Section 3 — Scenario: grype scan writes a parseable JSON report
# -----------------------------------------------------------------------------
say "3. grype scan JSON is well-formed"
test -f "$GRYPE"
jq -e '.descriptor.name == "grype"' "$GRYPE" >/dev/null
pass "$GRYPE has .descriptor.name == grype"

# -----------------------------------------------------------------------------
# Section 4 — Scenario: Local sign + verify round-trip
# -----------------------------------------------------------------------------
say "4. local cosign sign + verify round-trip"
make sign-local IMAGE_DIR="$IMAGE_DIR"
make verify     IMAGE_DIR="$IMAGE_DIR"
pass "sign-local + verify both exit 0"

# -----------------------------------------------------------------------------
# Section 5 — Scenario: non-publish CI is scan-only
# -----------------------------------------------------------------------------
# Static check — ci.yml must not run `docker push` or `cosign sign` and must
# not request id-token:write. Keyless signing lives only in build.yml.
say "5. .github/workflows/ci.yml is scan-only (no push, no keyless sign)"
test -f .github/workflows/ci.yml
if grep -E '^[[:space:]]*(docker push|cosign sign)' .github/workflows/ci.yml >/dev/null; then
  echo "  ✗ ci.yml must not push or sign" >&2
  exit 1
fi
if grep -E 'id-token:[[:space:]]*write' .github/workflows/ci.yml >/dev/null; then
  echo "  ✗ ci.yml must not request id-token: write" >&2
  exit 1
fi
pass "ci.yml has no push, no sign, no id-token write"

# -----------------------------------------------------------------------------
# Section 6 — Scenarios requiring a published digest (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "6. external cosign verify against the published digest"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "$IMAGE_PUBLISHED" >/dev/null
  pass "cosign verify exits 0 for $IMAGE_PUBLISHED"

  say "7. attestations are attached"
  cosign download attestation --predicate-type cyclonedx "$IMAGE_PUBLISHED" >/dev/null
  pass "CycloneDX SBOM attestation attached"
  cosign download attestation --predicate-type vuln "$IMAGE_PUBLISHED" >/dev/null
  pass "grype vuln attestation attached"

  say "8. anonymous pull works"
  docker logout ghcr.io 2>/dev/null || true
  docker pull "$IMAGE_PUBLISHED" >/dev/null
  pass "docker pull $IMAGE_PUBLISHED succeeds unauthenticated"
else
  say "6-8. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-001 acceptance: all sections passed."
