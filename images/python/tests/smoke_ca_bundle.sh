#!/usr/bin/env bash
# Smoke — system CA bundle present and readable at the Debian path.
#
# Delivers: FG-002 Scenario "CA bundle is present and readable".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
CA_PATH="/etc/ssl/certs/ca-certificates.crt"

docker run --rm "${IMAGE}" test -r "${CA_PATH}"
echo "  ✓ ${CA_PATH} readable"
