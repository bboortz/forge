#!/usr/bin/env bash
# Smoke — pip resolves and dry-runs a real wheel (`requests` because it
# exercises TLS and the CA path end-to-end).
#
# Delivers: FG-002 Scenario "pip resolves and dry-runs a real wheel".
#
# Requires network connectivity to PyPI. Known-flaky on blipped networks —
# we accept this per design decision (dry-run exercises the real resolve
# path that consumers hit).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm "${IMAGE}" pip install --dry-run --quiet requests >/dev/null
echo "  ✓ pip install --dry-run requests ok"
