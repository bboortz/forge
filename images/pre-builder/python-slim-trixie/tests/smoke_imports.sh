#!/usr/bin/env bash
# Smoke — Python core stdlib imports.
#
# Delivers: FG-002 Scenario "Python core stdlib is present".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.14-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE}" python3 -c "import ssl, hashlib, json, urllib.request" >/dev/null
echo "  ✓ stdlib imports ok (ssl, hashlib, json, urllib.request)"
