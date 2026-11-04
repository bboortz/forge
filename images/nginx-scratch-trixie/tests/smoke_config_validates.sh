#!/usr/bin/env bash
# Smoke — nginx validates its shipped config (nginx -t).
#
# Delivers: FG-006 Scenario "nginx validates its shipped config".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

set +e
out=$(docker run --rm "${IMAGE}" -t 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ docker run ${IMAGE} -t exited ${rc}" >&2
  echo "${out}" >&2
  exit 1
fi
if ! grep -q 'syntax is ok' <<<"${out}"; then
  echo "  ✗ 'syntax is ok' missing from nginx -t output:" >&2
  echo "${out}" >&2
  exit 1
fi
if ! grep -q 'test is successful' <<<"${out}"; then
  echo "  ✗ 'test is successful' missing from nginx -t output:" >&2
  echo "${out}" >&2
  exit 1
fi
echo "  ✓ nginx -t passes"
