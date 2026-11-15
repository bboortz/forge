#!/usr/bin/env bash
# Smoke — prometheus binary executes and reports version.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ prometheus --version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
# FG-053: floating :latest, resolved via GitHub Releases API each build.
# Accept any vX.Y.Z as long as it identifies as prometheus.
case "${out}" in
  *"prometheus, version "*) ;;
  *) echo "  ✗ unexpected --version output: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ $(echo "${out}" | head -1)"
