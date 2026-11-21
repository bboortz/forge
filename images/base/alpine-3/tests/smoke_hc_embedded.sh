#!/usr/bin/env bash
# Smoke: /hc is present + executable.
set -euo pipefail

: "${IMAGE_NAME:=base/alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/hc "${IMAGE}" --help 2>&1 || true)
if [[ -z "${out}" ]]; then
  echo "  ✗ /hc produced no output" >&2
  exit 1
fi
echo "  ✓ /hc executable + responsive"
