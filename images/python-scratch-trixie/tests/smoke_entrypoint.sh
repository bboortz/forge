#!/usr/bin/env bash
# Smoke — image runs Python code via `docker run <image> script.py` style.
# FG-009: python-scratch-trixie now uses ENTRYPOINT ["python3"] + empty CMD
# (distroless convention), so `docker run <image> -c "..."` just works
# without the consumer specifying python3 explicitly.
#
# Delivers: FG-002 "Container entrypoint runs python3 by default" +
#           FG-009 "ENTRYPOINT=python3 convention".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 1. docker run <image> -c "..." → ENTRYPOINT=python3 applies → runs python3 -c "..."
out=$(docker run --rm "${IMAGE}" -c "print('ok')")
if [[ "${out}" != "ok" ]]; then
  echo "  ✗ docker run <image> -c \"print('ok')\" returned '${out}', expected 'ok'" >&2
  exit 1
fi

# 2. docker run <image> (no args) → python3 REPL. Send EOF via stdin, expect
# clean exit.
: | docker run --rm -i "${IMAGE}" >/dev/null

echo "  ✓ docker run <image> -c runs python3 code; default (no args) starts REPL"
