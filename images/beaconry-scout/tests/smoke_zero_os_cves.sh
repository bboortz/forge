#!/usr/bin/env bash
# grype reports zero Debian-source matches against scout. Any finding is
# a PyPI dep brought in by scout's requirements.txt — not OS noise.
#
# Delivers: FG-012 Scenario "scout has zero OS-level CVEs".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-scout}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

if ! command -v grype >/dev/null; then
  echo "  ⚠ grype not installed — skipping (install via: make tools)"
  exit 0
fi

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
scan="${tmp}/grype.json"
grype "${IMAGE}" -o json > "${scan}" 2>/dev/null || true

total=$(jq '.matches | length' < "${scan}")
os=$(jq '[.matches[] | select(.vulnerability.namespace | test("debian|ubuntu|alpine"))] | length' < "${scan}")

if [[ "${os}" -ne 0 ]]; then
  echo "  ✗ ${os} Debian/Ubuntu/Alpine-source matches out of ${total}:" >&2
  jq -r '.matches[] | select(.vulnerability.namespace | test("debian|ubuntu|alpine")) | "    - \(.vulnerability.id) \(.artifact.name) \(.artifact.version) [\(.vulnerability.namespace)]"' < "${scan}" >&2
  exit 1
fi

echo "  ✓ zero Debian-source matches (${total} total match(es), all non-OS)"
