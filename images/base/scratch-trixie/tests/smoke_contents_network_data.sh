#!/usr/bin/env bash
# Baseline network-resolution contract (FG-008): /etc/services + /etc/protocols
# + /etc/hosts must be present so stdlib socket calls (getservbyname,
# getprotobyname, localhost lookup) work without docker-injected files.
#
# Delivers: FG-008 Scenario "baseline provides network-resolution data".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

paths=(etc/services etc/protocols etc/hosts)
for layer in "${tmp}"/blobs/sha256/*; do
  tar xf "${layer}" -C "${tmp}" "${paths[@]}" 2>/dev/null || true
done

for p in "${paths[@]}"; do
  if [[ ! -s "${tmp}/${p}" ]]; then
    echo "  ✗ /${p} missing or empty in ${IMAGE}" >&2
    exit 1
  fi
done

# Sanity-check well-known entries so a silent truncation would also fail.
if ! grep -qE '^http[[:space:]]+80/tcp' "${tmp}/etc/services"; then
  echo "  ✗ /etc/services missing 'http 80/tcp' — truncated or not shipped?" >&2
  exit 1
fi
if ! grep -qE '^tcp[[:space:]]+6' "${tmp}/etc/protocols"; then
  echo "  ✗ /etc/protocols missing 'tcp 6' — truncated or not shipped?" >&2
  exit 1
fi
if ! grep -q '127.0.0.1' "${tmp}/etc/hosts" || ! grep -q 'localhost' "${tmp}/etc/hosts"; then
  echo "  ✗ /etc/hosts missing localhost loopback" >&2
  exit 1
fi

echo "  ✓ /etc/services, /etc/protocols, /etc/hosts present with expected content"
