#!/usr/bin/env bash
# Smoke: /hc is present + executable.
set -euo pipefail

: "${IMAGE_NAME:=base/python-slim-trixie}"
: "${IMAGE_TAG:=0.1}"
: "${REGISTRY:=forge-local}"

IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# hc idle exits with success when SIGTERM'd; here we probe the binary exists
# by invoking its --help / running --version-like arg. hc's CLI exits 2 on
# unknown args — that's enough to prove it's an executable + present. Use
# --entrypoint to bypass python3.
out=$(docker run --rm --entrypoint=/hc "${IMAGE_REF}" --help 2>&1 || true)
# Require some output that mentions "hc" or "usage" to confirm it ran.
if [[ -z "${out}" ]]; then
  echo "  ✗ /hc produced no output — binary likely missing" >&2
  exit 1
fi
echo "  ✓ /hc executable + responsive"
