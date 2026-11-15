#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-alertmanager-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ prometheus-alertmanager --version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
# FG-052: floating :latest, resolved via GitHub Releases API each build.
# Accept any v0.X.Y as long as the binary identifies itself as alertmanager.
case "${out}" in
  *"alertmanager, version 0."*) ;;
  *) echo "  ✗ unexpected --version output: ${out}" >&2; exit 1 ;;
esac
echo "  ✓ $(echo "${out}" | head -1)"
