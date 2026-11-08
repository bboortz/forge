#!/usr/bin/env bash
# Smoke — real HTTPS end-to-end via urllib.
#
# Exists because the previous `smoke_tls_handshake.sh` only created an
# ssl.create_default_context() — lazy, never touched the trust store. It
# passed even when SSL_CERT_FILE wasn't set and every real HTTPS call
# would have failed with CERTIFICATE_VERIFY_FAILED. That blindspot slipped
# past our smoke gate until Beaconry (consumer) hit it with a real urlopen.
#
# FG-009: this test EXERCISES SSL_CERT_FILE propagation + the baseline CA
# bundle + nss DNS resolution + ENTRYPOINT=python3 all at once.
#
# Network-dependent: requires outbound HTTPS to example.com (TLS handshake
# + full response); known-flaky on blipped networks — accepted trade-off.
#
# Delivers: FG-009 Scenario "python-scratch does real HTTPS out of the box".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=python3 "${IMAGE}" -c "
import urllib.request
r = urllib.request.urlopen('https://example.com', timeout=15)
print(r.status)
" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ docker run exited ${rc}, HTTPS failed:" >&2
  echo "${out}" >&2
  exit 1
fi
if [[ "${out}" != "200" ]]; then
  echo "  ✗ expected HTTP 200, got: ${out}" >&2
  exit 1
fi
echo "  ✓ urllib.request.urlopen(https://example.com) returned 200"
