#!/usr/bin/env bash
# Baseline has no dpkg database → grype must find zero Debian-source matches.
# If grype flags anything, the baseline is leaking OS metadata somewhere
# (e.g. leftover /var/lib/dpkg/).
#
# Delivers: FG-005 Scenario "baseline has zero Debian-source CVEs".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

command -v grype >/dev/null || { echo "  ✗ grype not in PATH" >&2; exit 1; }
command -v jq    >/dev/null || { echo "  ✗ jq not in PATH"    >&2; exit 1; }

tmp=$(mktemp); trap 'rm -f "${tmp}"' EXIT
grype "${IMAGE}" -o json > "${tmp}" 2>/dev/null

deb=$(jq '[.matches[]? | select(.artifact.type == "deb" or .artifact.type == "dpkg")] | length' "${tmp}")
if [[ "${deb}" -ne 0 ]]; then
  echo "  ✗ baseline has ${deb} Debian/dpkg matches — OS metadata is leaking" >&2
  jq -r '.matches[]? | select(.artifact.type == "deb" or .artifact.type == "dpkg") | "    - " + .vulnerability.id + " via " + .artifact.name' "${tmp}" >&2
  exit 1
fi
total=$(jq '.matches | length' "${tmp}")
echo "  ✓ zero Debian-source matches (${total} total match(es), all non-OS)"
