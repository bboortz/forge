#!/usr/bin/env bash
# Baseline must contain no shell. Validated via `docker save` tar
# inspection since scratch has no exec to test interactively.
#
# Delivers: FG-005 Scenario "baseline contains no shell".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

bad_paths=(
  "bin/sh" "usr/bin/sh" "usr/bin/bash" "bin/bash" "bin/dash" "bin/busybox"
)

for layer in "${tmp}"/blobs/sha256/*; do
  listing=$(tar tf "${layer}" 2>/dev/null || true)
  for p in "${bad_paths[@]}"; do
    if grep -qxF "${p}" <<<"${listing}"; then
      echo "  ✗ shell present in baseline: ${p}" >&2
      exit 1
    fi
  done
done
echo "  ✓ no shell binaries in baseline"
