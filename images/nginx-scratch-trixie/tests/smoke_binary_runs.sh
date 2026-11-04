#!/usr/bin/env bash
# Smoke — nginx binary reports its version.
#
# Delivers: FG-006 Scenario "nginx binary reports version".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Capture output + exit code explicitly so a crash inside $(...) doesn't
# vanish into set -e. CI failure on PR #9 exposed this — the docker-run
# exited non-zero but set -e killed the script before the error could print.
set +e
out=$(docker run --rm "${IMAGE}" -v 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ docker run ${IMAGE} -v exited ${rc}" >&2
  echo "${out}" >&2
  exit 1
fi
if ! grep -q 'nginx/1\.26' <<<"${out}"; then
  echo "  ✗ expected 'nginx/1.26' in -v output, got: ${out}" >&2
  exit 1
fi
echo "  ✓ ${out}"
