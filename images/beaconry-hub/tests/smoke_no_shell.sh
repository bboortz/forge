#!/usr/bin/env bash
# No shell binary in hub. Inherited from python-scratch-trixie base.
#
# Delivers: FG-014 Scenario "hub inherits absence.shell".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-beaconry-hub}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

paths_file="${tmp}/all_paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths_file}"

bad=(bin/sh usr/bin/sh bin/bash usr/bin/bash bin/dash bin/busybox)
found=0
for p in "${bad[@]}"; do
  if grep -qxF "${p}" "${paths_file}"; then
    echo "  ✗ shell binary found: /${p}" >&2
    found=1
  fi
done
[[ ${found} -eq 1 ]] && exit 1
echo "  ✓ no shell binaries in hub image"
