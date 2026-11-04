#!/usr/bin/env bash
# Smoke — Python core stdlib imports.
#
# Delivers: FG-002 Scenario "Python core stdlib is present".
# FG-009: python-scratch-trixie uses ENTRYPOINT ["python3"] so explicit
# --entrypoint override ensures the test works regardless of variant.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.13}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=python3 "${IMAGE}" \
  -c "import ssl, hashlib, json, urllib.request" >/dev/null
echo "  ✓ stdlib imports ok (ssl, hashlib, json, urllib.request)"
