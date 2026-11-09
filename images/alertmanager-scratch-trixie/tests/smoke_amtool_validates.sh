#!/usr/bin/env bash
# Smoke — amtool validates the shipped default alertmanager.yml via docker exec.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-alertmanager-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.28}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CID="fg036-amtool-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null

sleep 2

set +e
out=$(docker exec "${CID}" /usr/bin/amtool check-config /etc/alertmanager/alertmanager.yml 2>&1)
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then
  echo "  ✗ amtool check-config exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
case "${out}" in
  *"SUCCESS"*|*"Checking"*|*"OK"*) ;;
  *) echo "  ✗ amtool output unexpected:" >&2; echo "${out}" >&2; exit 1 ;;
esac
echo "  ✓ docker exec amtool check-config → OK"
