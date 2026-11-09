#!/usr/bin/env bash
# Smoke — grype finds zero Debian-source matches (no dpkg DB).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT
grype "${IMAGE}" -o json > "${TMP}" 2>/dev/null

total=$(jq '.matches | length' "${TMP}")
debian=$(jq '[.matches[] | select(.vulnerability.namespace | test("debian"))] | length' "${TMP}")

[[ "${debian}" -eq 0 ]] \
  || { echo "  ✗ expected 0 Debian-source matches, got ${debian} (total ${total})" >&2; exit 1; }
echo "  ✓ zero Debian-source matches (grype reports ${total} total — all non-OS)"
