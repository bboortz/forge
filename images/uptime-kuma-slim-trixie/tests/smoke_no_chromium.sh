#!/usr/bin/env bash
# Smoke — Chromium / Playwright browsers are deliberately NOT shipped.
# Browser-based synthetic monitors (Playwright) are out of scope for this
# slim variant. An operator who tries to use one gets a clear error from
# uptime-kuma instead of a silent failure.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-uptime-kuma-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

for p in /usr/bin/chromium /usr/bin/chromium-browser /usr/bin/chrome /opt/google/chrome/chrome; do
  set +e
  docker run --rm --entrypoint=/usr/bin/test "${IMAGE}" -e "${p}" 2>&1
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    echo "  ✗ unexpected ${p} present (Chromium leaked into slim image)" >&2
    exit 1
  fi
done

# Playwright browser cache
set +e
docker run --rm --entrypoint=/usr/bin/test "${IMAGE}" -d /ms-playwright 2>&1
rc=$?
docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c '[ -d /home/node/.cache/ms-playwright ]' 2>&1
pw_rc=$?
set -e
if [[ "${rc}" -eq 0 || "${pw_rc}" -eq 0 ]]; then
  echo "  ✗ /ms-playwright or ~/.cache/ms-playwright present (browser cache leaked)" >&2
  exit 1
fi

echo "  ✓ no Chromium / Playwright browsers shipped (slim contract)"
