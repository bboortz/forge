#!/usr/bin/env bash
# Smoke — promtool exists in the runtime and validates the shipped
# default prometheus.yml.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CID="fg035-promtool-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null

# Wait a moment for the container to settle.
sleep 2

set +e
out=$(docker exec "${CID}" /usr/bin/promtool check config /etc/prometheus/prometheus.yml 2>&1)
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then
  echo "  ✗ promtool check config exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
case "${out}" in
  *"SUCCESS"*) ;;
  *) echo "  ✗ promtool output didn't mention SUCCESS:" >&2; echo "${out}" >&2; exit 1 ;;
esac
echo "  ✓ docker exec promtool check config /etc/prometheus/prometheus.yml → SUCCESS"
