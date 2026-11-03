#!/usr/bin/env bash
# Smoke — system CA bundle present and readable at the Debian path. Uses
# python3 for the readability check so the test is variant-neutral (scratch
# has no `test` binary, no shell).
#
# Delivers: FG-002 Scenario "CA bundle is present and readable".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
CA_PATH="/etc/ssl/certs/ca-certificates.crt"

docker run --rm "${IMAGE}" python3 -c "
import os, sys
sys.exit(0 if os.access('${CA_PATH}', os.R_OK) else 1)
" >/dev/null
echo "  ✓ ${CA_PATH} readable"
