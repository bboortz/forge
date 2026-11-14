#!/usr/bin/env bash
# Smoke — GHA runner binary present + reports a v2.X.Y version.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-github-runner-noble}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm --entrypoint=/home/runner/bin/Runner.Listener "${IMAGE}" --version 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ Runner.Listener --version exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi

case "${out}" in
  2.*) echo "  ✓ GHA runner: ${out}" ;;
  v2.*) echo "  ✓ GHA runner: ${out}" ;;
  *) echo "  ✗ expected v2.X.Y runner version, got: ${out}" >&2; exit 1 ;;
esac
