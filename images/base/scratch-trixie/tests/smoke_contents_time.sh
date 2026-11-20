#!/usr/bin/env bash
# Baseline time contract (FG-008): /etc/localtime is a symlink to the UTC
# tzdata file. Many apps (postgres, nginx, Python's time stdlib) read
# /etc/localtime first; without it they fall through to inconsistent
# defaults depending on the lib version.
#
# Delivers: FG-008 Scenario "baseline provides /etc/localtime → UTC".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

# Extract /etc/localtime preserving symlinks.
for layer in "${tmp}"/blobs/sha256/*; do
  tar xf "${layer}" -C "${tmp}" etc/localtime 2>/dev/null || true
done

if [[ ! -L "${tmp}/etc/localtime" ]]; then
  echo "  ✗ /etc/localtime is not a symlink (should point at zoneinfo/Etc/UTC)" >&2
  ls -la "${tmp}/etc/localtime" >&2 || true
  exit 1
fi
target=$(readlink "${tmp}/etc/localtime")
case "${target}" in
  */zoneinfo/Etc/UTC|*/zoneinfo/UTC)
    echo "  ✓ /etc/localtime → ${target}"
    ;;
  *)
    echo "  ✗ /etc/localtime points at ${target}, expected .../zoneinfo/{Etc/,}UTC" >&2
    exit 1
    ;;
esac
