#!/usr/bin/env bash
# install-anchore-tool.sh — retry-wrapping wrapper around Anchore's
# install.sh script for syft / grype / cosign-adjacent tooling.
#
# GitHub's releases/download/* CDN flaps 504 periodically (observed
# 2026-11-08), causing `curl | sh` to fail. The upstream install.sh
# doesn't retry transient CDN failures — we wrap it.
#
# Usage:
#   scripts/install-anchore-tool.sh <tool> <dest-dir> [version]
#
#   tool      : syft | grype
#   dest-dir  : -b argument passed to install.sh
#   version   : optional version tag (e.g. v1.57.0); install.sh picks
#               latest if omitted.
#
# Exits 0 on success, non-zero after 5 failed attempts.

set -euo pipefail

TOOL="${1:?usage: $0 <tool> <dest-dir> [version]}"
DEST="${2:?usage: $0 <tool> <dest-dir> [version]}"
VERSION="${3:-}"

INSTALL_URL="https://raw.githubusercontent.com/anchore/${TOOL}/main/install.sh"
MAX_ATTEMPTS=5

# shellcheck disable=SC2206  # VERSION intentionally word-splits (empty → no arg; "v1.57.0" → one arg)
VERSION_ARGS=(${VERSION})

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
  if curl -sSfL "${INSTALL_URL}" | sh -s -- -b "${DEST}" "${VERSION_ARGS[@]}"; then
    # install.sh exited 0 — but double-check the binary is actually there,
    # in case the script failed silently on a partial download.
    if [[ -x "${DEST}/${TOOL}" ]]; then
      echo "install-anchore-tool: ${TOOL} installed to ${DEST}/${TOOL} on attempt ${attempt}"
      exit 0
    fi
  fi
  if [[ "${attempt}" -lt "${MAX_ATTEMPTS}" ]]; then
    delay=$((attempt * 5))
    echo "install-anchore-tool: ${TOOL} install attempt ${attempt}/${MAX_ATTEMPTS} failed; retrying in ${delay}s" >&2
    sleep "${delay}"
  fi
done

echo "install-anchore-tool: ${TOOL} install failed after ${MAX_ATTEMPTS} attempts" >&2
exit 1
