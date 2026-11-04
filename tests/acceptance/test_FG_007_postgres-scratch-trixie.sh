#!/usr/bin/env bash
#
# Covers: FG-007
# CAPs:   image.postgres-serves-sql, test.sidecar-init,
#         image.no-shell, image.zero-os-cves, test.size-budget
#
# Encodes the Gherkin scenarios from
# docs/stories/FG-007-postgres-scratch-trixie.md.
#
# Red before implementation: images/postgres-scratch-trixie/ absent.
# Green once Dockerfile + smoke suite land and the image passes all 5
# scratch postgres scenarios.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-007]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE_DIR="postgres-scratch-trixie"
IMAGE="forge-local/${IMAGE_DIR}:17"

# -----------------------------------------------------------------------------
# Section 1 — image dir in place
# -----------------------------------------------------------------------------
say "1. images/${IMAGE_DIR}/ in place"
test -d "images/${IMAGE_DIR}"
test -f "images/${IMAGE_DIR}/Dockerfile"
test -f "images/${IMAGE_DIR}/image.yaml"
pass "scaffolding present"

# -----------------------------------------------------------------------------
# Section 2 — build succeeds via the central build script
# -----------------------------------------------------------------------------
say "2. scripts/build-image.sh ${IMAGE_DIR} produces ${IMAGE}"
bash scripts/build-image.sh "${IMAGE_DIR}" >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

# -----------------------------------------------------------------------------
# Section 3 — scratch postgres server passes its full smoke suite
# -----------------------------------------------------------------------------
say "3. smoke suite against scratch postgres"
bash "images/${IMAGE_DIR}/tests/smoke_binary_runs.sh"
bash "images/${IMAGE_DIR}/tests/smoke_no_shell.sh"
bash "images/${IMAGE_DIR}/tests/smoke_server_accepts.sh"
bash "images/${IMAGE_DIR}/tests/smoke_zero_os_cves.sh"
bash "images/${IMAGE_DIR}/tests/smoke_size.sh"

# -----------------------------------------------------------------------------
# Section 4 — postgres uid matches Docker Hub convention (999)
# -----------------------------------------------------------------------------
say "4. postgres user pinned to uid 999 (Docker Hub convention)"
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"
# Extract /etc/passwd from EVERY layer (don't break early) so the later
# overlay wins — baseline layer ships root+nobody; postgres overlay layer
# overwrites with the service-user augmented file.
for layer in "${tmp}"/blobs/sha256/*; do
  tar xf "${layer}" -C "${tmp}" etc/passwd 2>/dev/null || true
done
if ! grep -qE '^postgres:x:999:999:' "${tmp}/etc/passwd"; then
  echo "  ✗ postgres uid/gid not pinned to 999:999 in /etc/passwd:" >&2
  grep postgres "${tmp}/etc/passwd" >&2 || true
  exit 1
fi
pass "/etc/passwd pins postgres to uid 999"

# -----------------------------------------------------------------------------
# Section 5 — Post-publish (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "5. external cosign verify"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "ghcr.io/bboortz/${IMAGE_DIR}:17" >/dev/null
  pass "cosign verify exits 0 for the published postgres-scratch-trixie:17"
else
  say "5. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-007 acceptance: all sections passed."
