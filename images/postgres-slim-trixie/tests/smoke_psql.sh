#!/usr/bin/env bash
# Smoke: psql binary present + runnable.
set -euo pipefail

: "${IMAGE_NAME:=postgres-slim-trixie}"
: "${IMAGE_TAG:=18}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE_REF}: psql --version"
out=$(docker run --rm --entrypoint=/usr/bin/psql "${IMAGE_REF}" --version)
echo "  ${out}"
echo "${out}" | grep -qE "^psql \(PostgreSQL\) 18\." || {
  echo "  ✗ expected 'psql (PostgreSQL) 18.x'" >&2
  exit 1
}
echo "  ✓ psql 18 client present"
