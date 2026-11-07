#!/usr/bin/env bash
# FG-016: nginx-scratch-trixie bundles /usr/lib/nginx/modules/*.so so
# consumers with stream/ssl_preread configs can `load_module` without
# building a derived image.
#
# Delivers: FG-016 Scenario "dynamic modules are bundled".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

paths_file="${tmp}/all_paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths_file}"

required=(
  "usr/lib/nginx/modules/ngx_stream_module.so"
)
missing=0
for p in "${required[@]}"; do
  if ! grep -qxF "${p}" "${paths_file}"; then
    echo "  ✗ missing: /${p}" >&2
    missing=$((missing + 1))
  fi
done
[[ ${missing} -gt 0 ]] && exit 1

echo "  ✓ ngx_stream_module.so (incl. ssl_preread) present at /usr/lib/nginx/modules/"
