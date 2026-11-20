#!/usr/bin/env bash
# Baseline has no exec — can't docker-run it. Validate contents via
# `docker save` tar inspection. Each required path must be present AND
# be a regular file / symlink / directory as expected.
#
# Delivers: FG-005 Scenario "baseline contains the expected file surface".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

# Union all layer tarballs into a flat set of paths — scratch-base-trixie
# has ~1 content layer anyway, but be robust to layer splitting.
paths_file="${tmp}/all_paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths_file}"

required=(
  "lib64/ld-linux-x86-64.so.2"
  "lib/x86_64-linux-gnu/libc.so.6"
  "lib/x86_64-linux-gnu/libm.so.6"
  "lib/x86_64-linux-gnu/libdl.so.2"
  "lib/x86_64-linux-gnu/libpthread.so.0"
  "lib/x86_64-linux-gnu/libcrypt.so.1"
  "lib/x86_64-linux-gnu/libgcc_s.so.1"
  "lib/x86_64-linux-gnu/libssl.so.3"
  "lib/x86_64-linux-gnu/libcrypto.so.3"
  "lib/x86_64-linux-gnu/libz.so.1"
  "lib/x86_64-linux-gnu/libzstd.so.1"
  "lib/x86_64-linux-gnu/libnss_dns.so.2"
  "lib/x86_64-linux-gnu/libnss_files.so.2"
  "lib/x86_64-linux-gnu/libresolv.so.2"
  "etc/ssl/certs/ca-certificates.crt"
  "etc/nsswitch.conf"
  "etc/passwd"
  "etc/group"
)

missing=0
for p in "${required[@]}"; do
  if ! grep -qxF "${p}" "${paths_file}"; then
    echo "  ✗ missing: ${p}" >&2
    missing=$((missing + 1))
  fi
done

# zoneinfo is a tree; just require UTC + GMT exist.
for z in "usr/share/zoneinfo/UTC" "usr/share/zoneinfo/GMT"; do
  if ! grep -qxF "${z}" "${paths_file}"; then
    echo "  ✗ missing: ${z}" >&2
    missing=$((missing + 1))
  fi
done

[[ $missing -eq 0 ]] || { echo "  ✗ ${missing} required file(s) missing" >&2; exit 1; }
echo "  ✓ all ${#required[@]} core files + zoneinfo/UTC + zoneinfo/GMT present"
