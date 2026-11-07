#!/usr/bin/env bash
# Smoke: mosquitto server binary runs; client binaries run.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mosquitto-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "→ ${IMAGE}: mosquitto --help"
out=$(docker run --rm "${IMAGE}" -h 2>&1 || true)
if ! grep -qE 'mosquitto version 2\.' <<<"${out}"; then
  echo "  ✗ expected 'mosquitto version 2.' in output, got: ${out}" >&2
  exit 1
fi
echo "  ✓ mosquitto v2 runs"

echo "→ ${IMAGE}: mosquitto_sub --help"
out=$(docker run --rm --entrypoint=/usr/bin/mosquitto_sub "${IMAGE}" --help 2>&1 || true)
if ! grep -qE 'mosquitto_sub version 2\.' <<<"${out}"; then
  echo "  ✗ expected 'mosquitto_sub version 2.' somewhere in --help" >&2
  echo "${out}" | head -5 >&2
  exit 1
fi
echo "  ✓ mosquitto_sub v2 runs"

echo "→ ${IMAGE}: mosquitto_pub --help"
out=$(docker run --rm --entrypoint=/usr/bin/mosquitto_pub "${IMAGE}" --help 2>&1 || true)
if ! grep -qE 'mosquitto_pub version 2\.' <<<"${out}"; then
  echo "  ✗ expected 'mosquitto_pub version 2.' somewhere in --help" >&2
  echo "${out}" | head -5 >&2
  exit 1
fi
echo "  ✓ mosquitto_pub v2 runs"

echo "→ ${IMAGE}: mosquitto_passwd (hash generator) runs"
out=$(docker run --rm --entrypoint=/usr/bin/mosquitto_passwd "${IMAGE}" -h 2>&1 | head -1 || true)
if ! grep -qE 'mosquitto_passwd is a tool' <<<"${out}"; then
  echo "  ✗ expected mosquitto_passwd banner" >&2
  exit 1
fi
echo "  ✓ mosquitto_passwd runs"
