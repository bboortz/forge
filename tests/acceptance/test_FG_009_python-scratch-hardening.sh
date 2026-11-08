#!/usr/bin/env bash
#
# Covers: FG-009
# CAPs:   image.ssl-cert-env, image.python-scratch-nonroot,
#         test.image-smoke-suite, test.scratch-contents
#
# Encodes the Gherkin scenarios from
# docs/stories/FG-009-python-scratch-hardening.md.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-009]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/python-scratch-trixie:3.14"

# -----------------------------------------------------------------------------
# Section 1 — build python-scratch-trixie
# -----------------------------------------------------------------------------
say "1. python-scratch-trixie builds with hardening"
bash scripts/build-image.sh python-scratch-trixie >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

# -----------------------------------------------------------------------------
# Section 2 — Beaconry claim 1: HTTPS works out of the box
# -----------------------------------------------------------------------------
say "2. HTTPS works out of the box (Beaconry claim 1)"
bash images/python-scratch-trixie/tests/smoke_tls_https_real.sh

# -----------------------------------------------------------------------------
# Section 3 — Beaconry claim 2 + 3: nonroot runtime + USER baked
# -----------------------------------------------------------------------------
say "3. runs as nonroot (uid 65532) by default (Beaconry claims 2+3)"
bash images/python-scratch-trixie/tests/smoke_user_nonroot.sh

# -----------------------------------------------------------------------------
# Section 4 — Beaconry claim 4: ENTRYPOINT=python3
# -----------------------------------------------------------------------------
say "4. ENTRYPOINT = python3 (Beaconry claim 4)"
got=$(docker image inspect "${IMAGE}" --format '{{json .Config.Entrypoint}}')
if [[ "${got}" != '["/usr/local/bin/python3"]' ]]; then
  echo "  ✗ .Config.Entrypoint is ${got}, expected [\"/usr/local/bin/python3\"]" >&2
  exit 1
fi
pass ".Config.Entrypoint = [\"/usr/local/bin/python3\"]"

bash images/python-scratch-trixie/tests/smoke_entrypoint.sh

# -----------------------------------------------------------------------------
# Section 5 — Beaconry claim 5: PYTHON* env baked
# -----------------------------------------------------------------------------
say "5. SSL_CERT_FILE + SSL_CERT_DIR + PYTHON* env baked (Beaconry claim 5)"
env_json=$(docker image inspect "${IMAGE}" --format '{{json .Config.Env}}')
for required in \
    "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" \
    "SSL_CERT_DIR=/etc/ssl/certs" \
    "PYTHONDONTWRITEBYTECODE=1" \
    "PYTHONFAULTHANDLER=1"; do
  if ! grep -q "${required}" <<<"${env_json}"; then
    echo "  ✗ .Config.Env missing ${required}" >&2
    echo "  Env: ${env_json}" >&2
    exit 1
  fi
done
pass "all 4 required env vars present in image config"

# -----------------------------------------------------------------------------
# Section 6 — every scratch derivative re-declares SSL_CERT_FILE
# -----------------------------------------------------------------------------
say "6. every scratch derivative Dockerfile re-declares SSL_CERT_FILE"
for d in python-scratch-trixie nginx-scratch-trixie postgres-scratch-trixie; do
  if ! grep -qE 'SSL_CERT_FILE=/etc/ssl/certs/ca-certificates\.crt' \
         "images/${d}/Dockerfile"; then
    echo "  ✗ images/${d}/Dockerfile missing SSL_CERT_FILE env" >&2
    exit 1
  fi
done
pass "all 3 scratch derivatives re-declare SSL_CERT_FILE"

# -----------------------------------------------------------------------------
# Section 7 — memory/scratch-closures.md documents the ENV-doesn't-propagate trap
# -----------------------------------------------------------------------------
say "7. memory/scratch-closures.md flags the ENV-propagation trap"
if ! grep -qiE 'env (directive )?(does|do) ?not (propagate|flow)' memory/scratch-closures.md; then
  echo "  ✗ memory/scratch-closures.md doesn't document the ENV-propagation trap" >&2
  exit 1
fi
pass "ENV-propagation warning present in memory/scratch-closures.md"

# -----------------------------------------------------------------------------
# Section 8 — Post-publish (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "8. external cosign verify + Beaconry's original failing command works"
  cosign verify \
    --certificate-identity "https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "ghcr.io/bboortz/python-scratch-trixie:3.14" >/dev/null
  pass "cosign verify ghcr.io/bboortz/python-scratch-trixie:3.14"

  docker run --rm ghcr.io/bboortz/python-scratch-trixie:3.14 \
    -c "import urllib.request; print(urllib.request.urlopen('https://example.com').status)" \
    | grep -qx 200
  pass "ghcr.io/bboortz/python-scratch-trixie:3.14 serves HTTPS 200 out of the box"
else
  say "8. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-009 acceptance: all sections passed."
