#!/usr/bin/env bash
# Smoke — /etc/os-release reports the sid release.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-debian-slim-sid}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/bin/cat "${IMAGE}" /etc/os-release 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ cat /etc/os-release failed (rc=${rc}):" >&2
  echo "${out}" >&2
  exit 1
fi

# Debian sid's /etc/os-release reports:
#   NAME="Debian GNU/Linux"
#   ID=debian
#   VERSION_CODENAME=trixie  (during freeze) OR unstable/sid (post-release)
# Rolling-release so the precise codename varies. Acceptable signals:
#   - VERSION_CODENAME=sid
#   - VERSION_CODENAME=unstable
#   - PRETTY_NAME contains "sid" or "unstable"
#   - Debian version is more recent than trixie (13 → 14 "forky" at times)
echo "${out}" | grep -q 'ID=debian' \
  || { echo "  ✗ not a Debian image:" >&2; echo "${out}" >&2; exit 1; }

# Any of these are acceptable sid markers
if echo "${out}" | grep -qE 'VERSION_CODENAME=(sid|unstable)' \
   || echo "${out}" | grep -qiE 'PRETTY_NAME=.*(sid|unstable|forky)'; then
  marker=$(echo "${out}" | grep -E 'VERSION_CODENAME=|PRETTY_NAME=' | head -1)
  echo "  ✓ Debian sid detected: ${marker}"
else
  # Fallback: as of trixie=13 stable, sid is typically unlabeled or forky.
  # If VERSION_ID is absent entirely, it's unstable.
  if ! echo "${out}" | grep -q '^VERSION_ID='; then
    echo "  ✓ Debian unstable (no VERSION_ID — sid convention)"
  else
    echo "  ✗ Debian detected but not sid/unstable:" >&2
    echo "${out}" | grep -E 'VERSION|ID' >&2
    exit 1
  fi
fi
