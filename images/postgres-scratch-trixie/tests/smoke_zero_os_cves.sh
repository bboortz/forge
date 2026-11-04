#!/usr/bin/env bash
# Smoke — grype against postgres-scratch-trixie reports zero matches whose
# source is a Debian package.
#
# Delivers: FG-007 Scenario "zero Debian-source CVEs".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-17}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

command -v grype >/dev/null || { echo "  ✗ grype not in PATH" >&2; exit 1; }
command -v jq    >/dev/null || { echo "  ✗ jq not in PATH"    >&2; exit 1; }

tmp=$(mktemp); trap 'rm -f "${tmp}"' EXIT
grype "${IMAGE}" -o json > "${tmp}" 2>/dev/null

deb_matches=$(jq '[.matches[]? | select(.artifact.type == "deb" or .artifact.type == "dpkg")] | length' "${tmp}")
if [[ "${deb_matches}" -ne 0 ]]; then
  echo "  ✗ grype found ${deb_matches} Debian/dpkg matches:" >&2
  jq -r '.matches[]? | select(.artifact.type == "deb" or .artifact.type == "dpkg") | "    - " + .vulnerability.id + " via " + .artifact.name' "${tmp}" >&2
  exit 1
fi
echo "  ✓ zero Debian-source matches (grype reports $(jq '.matches | length' "${tmp}") total match(es) — all non-OS)"
