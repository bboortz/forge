#!/usr/bin/env bash
# Smoke: corepack is enabled + npm/pnpm/yarn all resolve a version.
# Also smokes git/curl/jq (release-resolve tools) + make/g++/python3
# (native-dep toolchain) + apt-upgraded state (no cache files).
set -euo pipefail
: "${IMAGE_NAME:=forge-builder-node-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# npm ships with Node — must respond.
docker run --rm --entrypoint=/usr/local/bin/npm "${IMAGE_REF}" --version >/dev/null \
  || { echo "  ✗ npm --version failed" >&2; exit 1; }
echo "  ✓ npm responds"

# pnpm + yarn via corepack shims. First invocation may download the pinned
# version (reads packageManager from package.json; without one, uses the
# version `corepack prepare` baked in). We just need them to RESPOND, not
# to have a specific version.
docker run --rm --entrypoint=/usr/local/bin/pnpm "${IMAGE_REF}" --version >/dev/null \
  || { echo "  ✗ pnpm shim missing or broken" >&2; exit 1; }
echo "  ✓ pnpm responds via corepack shim"

docker run --rm --entrypoint=/usr/local/bin/yarn "${IMAGE_REF}" --version >/dev/null \
  || { echo "  ✗ yarn shim missing or broken" >&2; exit 1; }
echo "  ✓ yarn responds via corepack shim"

# Release-resolve tools.
for bin in git curl jq; do
  docker run --rm --entrypoint="/usr/bin/${bin}" "${IMAGE_REF}" --version >/dev/null \
    || { echo "  ✗ ${bin} missing" >&2; exit 1; }
done
echo "  ✓ git + curl + jq present (release-resolve tools)"

# Native-dep toolchain.
docker run --rm --entrypoint=/usr/bin/make "${IMAGE_REF}" --version >/dev/null \
  || { echo "  ✗ make missing" >&2; exit 1; }
docker run --rm --entrypoint=/usr/bin/g++ "${IMAGE_REF}" --version >/dev/null \
  || { echo "  ✗ g++ missing" >&2; exit 1; }
docker run --rm --entrypoint=/usr/bin/python3 "${IMAGE_REF}" --version >/dev/null \
  || { echo "  ✗ python3 missing" >&2; exit 1; }
echo "  ✓ make + g++ + python3 present (native-dep toolchain)"

# CA bundle.
docker run --rm --entrypoint=/usr/bin/test "${IMAGE_REF}" -f /etc/ssl/certs/ca-certificates.crt \
  || { echo "  ✗ /etc/ssl/certs/ca-certificates.crt missing" >&2; exit 1; }
echo "  ✓ CA bundle present"

# apt cache cleared (apt.no-cache invariant).
set +e
files=$(docker run --rm --entrypoint=/bin/sh "${IMAGE_REF}" -c \
        'ls /var/lib/apt/lists/ 2>/dev/null | grep -vE "^partial$|^auxfiles$|^lock$" | wc -l')
set -e
if [[ "${files}" -gt 0 ]]; then
  echo "  ✗ /var/lib/apt/lists/ carries ${files} cache file(s) — apt.no-cache violated" >&2
  exit 1
fi
echo "  ✓ apt cache cleared"
