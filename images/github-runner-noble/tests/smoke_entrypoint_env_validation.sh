#!/usr/bin/env bash
# Smoke — entrypoint.sh fails fast (not hangs) if GITHUB_ORG is unset
# and no prior .runner registration exists. Catches the regression
# class where entrypoint hangs forever on missing env.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-github-runner-noble}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Run WITHOUT GITHUB_ORG set. Expect immediate nonzero exit + clear stderr.
set +e
out=$(timeout 10 docker run --rm "${IMAGE}" 2>&1)
rc=$?
set -e

# Expected: rc=1 (exit from our check) or rc=124 (shouldn't — would mean
# it hung past timeout).
if [[ ${rc} -eq 124 ]]; then
  echo "  ✗ entrypoint hung instead of failing fast" >&2
  echo "${out}" >&2
  exit 1
fi
if [[ ${rc} -eq 0 ]]; then
  echo "  ✗ entrypoint exited 0 with missing env — expected nonzero" >&2
  echo "${out}" >&2
  exit 1
fi

# Error message should name GITHUB_ORG.
echo "${out}" | grep -q 'GITHUB_ORG' \
  || { echo "  ✗ entrypoint error didn't mention GITHUB_ORG:" >&2; echo "${out}" >&2; exit 1; }

echo "  ✓ entrypoint fails fast (rc=${rc}) with clear GITHUB_ORG error when env unset"
