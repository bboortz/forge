#!/usr/bin/env bash
# Smoke: postgres binary present + reports version 18.
set -euo pipefail

: "${IMAGE_NAME:=postgres-slim-trixie}"
: "${IMAGE_TAG:=18}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE_REF}: postgres --version"
out=$(docker run --rm --user=postgres --entrypoint=/usr/lib/postgresql/18/bin/postgres "${IMAGE_REF}" --version)
echo "  ${out}"
echo "${out}" | grep -qE "^postgres \(PostgreSQL\) 18\." || {
  echo "  ✗ expected 'postgres (PostgreSQL) 18.x'" >&2
  exit 1
}
echo "  ✓ postgres 18 present"
