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
# Exits 0 on success, non-zero after MAX_ATTEMPTS failed attempts.

set -euo pipefail

TOOL="${1:?usage: $0 <tool> <dest-dir> [version]}"
DEST="${2:?usage: $0 <tool> <dest-dir> [version]}"
VERSION="${3:-}"

INSTALL_URL="https://raw.githubusercontent.com/anchore/${TOOL}/main/install.sh"
# 10 attempts, exponential-ish backoff up to 60s between attempts. Total
# window: ~6 minutes. GitHub's release CDN typically recovers within that.
MAX_ATTEMPTS="${INSTALL_ANCHORE_MAX_ATTEMPTS:-10}"

# shellcheck disable=SC2206  # VERSION intentionally word-splits (empty → no arg; "v1.57.0" → one arg)
VERSION_ARGS=(${VERSION})

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
  if curl -sSfL --max-time 60 "${INSTALL_URL}" | sh -s -- -b "${DEST}" "${VERSION_ARGS[@]}"; then
    # install.sh exited 0 — but double-check the binary is actually there,
    # in case the script failed silently on a partial download.
    if [[ -x "${DEST}/${TOOL}" ]]; then
      echo "install-anchore-tool: ${TOOL} installed to ${DEST}/${TOOL} on attempt ${attempt}"
      exit 0
    fi
  fi
  if [[ "${attempt}" -lt "${MAX_ATTEMPTS}" ]]; then
    # Cap backoff at 60s so we spend more time trying than sleeping.
    delay=$((attempt * 6))
    [[ "${delay}" -gt 60 ]] && delay=60
    echo "install-anchore-tool: ${TOOL} install attempt ${attempt}/${MAX_ATTEMPTS} failed; retrying in ${delay}s" >&2
    sleep "${delay}"
  fi
done

echo "install-anchore-tool: ${TOOL} install failed after ${MAX_ATTEMPTS} attempts" >&2
exit 1
