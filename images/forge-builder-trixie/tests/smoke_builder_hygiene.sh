#!/usr/bin/env bash
# Smoke: forge-builder-trixie removed curl after syft install (apt.no-curl)
# and includes an apt-upgrade layer (apt.freshly-upgraded).

set -euo pipefail
: "${IMAGE_NAME:=forge-builder-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE_REF}: curl removed"
# docker run returns nonzero if curl is absent — we WANT that.
if docker run --rm --entrypoint=/usr/bin/which "${IMAGE_REF}" curl >/dev/null 2>&1; then
  echo "  ✗ curl still present — apt.no-curl violated" >&2
  exit 1
fi
echo "  ✓ curl removed"

echo "→ ${IMAGE_REF}: docker history mentions apt-get upgrade"
# `docker history --format` is more reliable than parsing the tabular output.
if ! docker history --format '{{.CreatedBy}}' --no-trunc "${IMAGE_REF}" 2>&1 | grep -q "apt-get.*upgrade"; then
  echo "  ✗ no apt-get upgrade step in layer history — apt.freshly-upgraded unverified" >&2
  exit 1
fi
echo "  ✓ apt-get upgrade executed in builder layer"
