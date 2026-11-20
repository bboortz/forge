#!/usr/bin/env bash
# Smoke — system CA bundle present and readable at the Debian path.
# FG-009: variant has ENTRYPOINT=python3; explicit --entrypoint override.
#
# Delivers: FG-002 Scenario "CA bundle is present and readable".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
CA_PATH="/etc/ssl/certs/ca-certificates.crt"

docker run --rm --entrypoint=python3 "${IMAGE}" -c "
import os, sys
sys.exit(0 if os.access('${CA_PATH}', os.R_OK) else 1)
" >/dev/null
echo "  ✓ ${CA_PATH} readable"
