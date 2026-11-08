#!/usr/bin/env bash
# Scratch — asserts grype against the runtime image reports zero matches
# whose source is a Debian package. Any CVE the consumer sees against this
# image must originate from a PyPI dep they installed themselves — not from
# an inherited OS package database.
#
# Delivers: FG-003 Scenario "grype against scratch finds zero Debian matches".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.14-scratch-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

command -v grype >/dev/null || { echo "  ✗ grype not in PATH — install via make tools" >&2; exit 1; }
command -v jq    >/dev/null || { echo "  ✗ jq not in PATH"                                >&2; exit 1; }

tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT

grype "${IMAGE}" -o json > "${tmp}" 2>/dev/null

deb_matches=$(jq '[.matches[]? | select(.artifact.type == "deb" or .artifact.type == "dpkg")] | length' "${tmp}")

if [[ "${deb_matches}" -ne 0 ]]; then
  echo "  ✗ grype found ${deb_matches} Debian/dpkg matches against scratch runtime" >&2
  jq -r '.matches[]? | select(.artifact.type == "deb" or .artifact.type == "dpkg") | "    - " + .vulnerability.id + " via " + .artifact.name' "${tmp}" >&2
  exit 1
fi

echo "  ✓ zero Debian-source matches (grype reports $(jq '.matches | length' "${tmp}") total match(es) — all non-OS)"
