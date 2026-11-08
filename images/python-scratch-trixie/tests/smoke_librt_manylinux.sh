#!/usr/bin/env bash
# FG-011 — librt.so.1 ABI stub is loadable from python-scratch-trixie so
# manylinux2014 / manylinux_2_17 wheels (numpy/scipy/pandas/pillow/…) can
# dlopen it. glibc 2.34 merged librt into libc; the 14.5 KB stub Debian
# still ships is what satisfies `NEEDED librt.so.1` in those wheels.
#
# Delivers: FG-011 "librt-manylinux-compat".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 1. File is present. Union all layer tar listings and grep fixed-string
# (same pattern as baseline smokes; robust to OCI non-tar blobs).
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"
paths_file="${tmp}/all_paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths_file}"
if ! grep -qxF 'lib/x86_64-linux-gnu/librt.so.1' "${paths_file}"; then
  echo "  ✗ /lib/x86_64-linux-gnu/librt.so.1 not present in image layers" >&2
  exit 1
fi

# 2. ctypes.CDLL("librt.so.1") succeeds at runtime — this is exactly what the
# dynamic loader does when a wheel's .so has NEEDED librt.so.1.
out=$(docker run --rm --entrypoint=/usr/local/bin/python3 "${IMAGE}" -c "
import ctypes
h = ctypes.CDLL('librt.so.1')
print('ok')
" 2>&1)
rc=$?
if [[ ${rc} -ne 0 || "${out}" != *ok* ]]; then
  echo "  ✗ dlopen(librt.so.1) failed (rc=${rc}): ${out}" >&2
  exit 1
fi

echo "  ✓ librt.so.1 present and dlopen-able (manylinux2014 wheel compat)"
