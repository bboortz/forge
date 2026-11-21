#!/usr/bin/env bash
# Smoke: /hc is present + executable + HEALTHCHECK baked in.
set -euo pipefail

: "${IMAGE_NAME:=psitransfer-slim-trixie}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

out=$(docker run --rm --entrypoint=/hc "${IMAGE}" --help 2>&1 || true)
if [[ -z "${out}" ]]; then
  echo "  ✗ /hc produced no output" >&2
  exit 1
fi

hc=$(docker image inspect --format '{{json .Config.Healthcheck}}' "${IMAGE}")
[[ "${hc}" != "null" ]] || { echo "  ✗ no HEALTHCHECK baked in" >&2; exit 1; }
echo "${hc}" | grep -q "/hc" || { echo "  ✗ HEALTHCHECK doesn't invoke /hc: ${hc}" >&2; exit 1; }

echo "  ✓ /hc executable + HEALTHCHECK baked"
