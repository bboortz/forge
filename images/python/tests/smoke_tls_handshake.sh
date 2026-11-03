#!/usr/bin/env bash
# Smoke — ssl.create_default_context() + TLS wiring (offline).
#
# Delivers: FG-002 Scenario "TLS context initializes".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE}" python3 -c "
import ssl
ctx = ssl.create_default_context()
assert ctx.verify_mode == ssl.CERT_REQUIRED, 'default context must verify'
assert ctx.check_hostname, 'default context must check_hostname'
" >/dev/null
echo "  ✓ ssl.create_default_context() usable"
