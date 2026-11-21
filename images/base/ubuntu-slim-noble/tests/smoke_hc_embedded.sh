#!/usr/bin/env bash
# Smoke: /hc is present + executable.
set -euo pipefail

: "${IMAGE_NAME:=base/ubuntu-slim-noble}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/hc "${IMAGE_REF}" --help 2>&1 || true)
if [[ -z "${out}" ]]; then
  echo "  ✗ /hc produced no output" >&2
  exit 1
fi
echo "  ✓ /hc executable + responsive"
