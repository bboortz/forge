#!/usr/bin/env bash
# Smoke — image runs Python code via `docker run <image> python3 ...`.
# The Dockerfile uses CMD (not ENTRYPOINT) to match upstream python:*-slim
# behaviour, so consumers invoke python3 explicitly when passing args.
# This test exercises that invocation pattern end-to-end.
#
# Delivers: FG-002 Scenario "Container entrypoint runs python3 by default".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python}"
IMAGE_TAG="${IMAGE_TAG:-3.13-slim-trixie}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm "${IMAGE}" python3 -c "print('ok')")
if [[ "${out}" != "ok" ]]; then
  echo "  ✗ expected 'ok', got: ${out}" >&2
  exit 1
fi

# And default CMD alone starts the python3 REPL without crashing (test by
# sending EOF via stdin and asserting zero exit).
: | docker run --rm -i "${IMAGE}" >/dev/null

echo "  ✓ python3 -c round-trips 'ok'; default CMD starts python3 cleanly"
