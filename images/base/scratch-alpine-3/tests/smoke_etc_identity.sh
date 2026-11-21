#!/usr/bin/env bash
# Smoke: /etc/passwd + /etc/group + /etc/hosts + /etc/nsswitch.conf contain
# expected entries.
set -euo pipefail

: "${IMAGE_NAME:=base/scratch-alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

for f in etc/passwd etc/group etc/hosts etc/nsswitch.conf; do
  for layer in "${tmp}"/blobs/sha256/*; do
    tar -xf "${layer}" -C "${tmp}" "${f}" 2>/dev/null && break || true
  done
done

grep -qE '^root:x:0:0' "${tmp}/etc/passwd"   || { echo "  ✗ /etc/passwd missing root"; exit 1; }
grep -qE '^nonroot:x:65532:' "${tmp}/etc/passwd" || { echo "  ✗ /etc/passwd missing nonroot (65532)"; exit 1; }
grep -qE '^nogroup:x:65534:' "${tmp}/etc/group"  || { echo "  ✗ /etc/group missing nogroup"; exit 1; }
grep -qE '^127\.0\.0\.1[[:space:]]+localhost' "${tmp}/etc/hosts" || { echo "  ✗ /etc/hosts missing localhost"; exit 1; }
grep -qE '^hosts:' "${tmp}/etc/nsswitch.conf" || { echo "  ✗ /etc/nsswitch.conf missing hosts policy"; exit 1; }
echo "  ✓ /etc identity present"
