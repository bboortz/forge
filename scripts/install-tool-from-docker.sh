#!/usr/bin/env bash
# install-tool-from-docker.sh — pull a Docker image and extract a binary to dest.
#
# Use when GitHub's release-asset CDN is flaky (observed 2026-11-08: sustained 504s
# on github.com/*/releases/download/*). Docker Hub is a different CDN and has been
# reliable during the same windows.
#
# Usage:
#   scripts/install-tool-from-docker.sh <image> <path-in-image> <dest>
#
#   image         : e.g. hadolint/hadolint:latest-debian
#   path-in-image : e.g. /bin/hadolint, /syft, /grype
#   dest          : e.g. /usr/local/bin/hadolint
#
# Exits 0 on success; non-zero on pull/cp failure.

set -euo pipefail

IMAGE="${1:?usage: $0 <image> <path-in-image> <dest>}"
BIN_IN_IMAGE="${2:?usage: $0 <image> <path-in-image> <dest>}"
DEST="${3:?usage: $0 <image> <path-in-image> <dest>}"

# docker pull has its own retry/backoff; retry 3× here as a defence in depth.
for attempt in 1 2 3; do
  if docker pull --quiet "${IMAGE}" >/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 3 ]]; then
    echo "install-tool-from-docker: docker pull failed after 3 attempts for ${IMAGE}" >&2
    exit 1
  fi
  echo "install-tool-from-docker: docker pull ${IMAGE} attempt ${attempt}/3 failed; retrying" >&2
  sleep $((attempt * 5))
done

CID=$(docker create "${IMAGE}")
docker cp "${CID}:${BIN_IN_IMAGE}" "${DEST}"
docker rm "${CID}" >/dev/null
chmod +x "${DEST}"

echo "install-tool-from-docker: extracted ${BIN_IN_IMAGE} from ${IMAGE} → ${DEST}"
