#!/usr/bin/env bash
# Smoke — /metrics returns Prometheus text format with cadvisor_version_info.
#
# cadvisor binds :8080 and always exposes /metrics; even without the
# full /:/rootfs + /var/lib/docker mounts, cadvisor_version_info + its
# own Go runtime metrics are always present.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cadvisor-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 8080 \
  --run-flags "-v /sys:/sys:ro" \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/metrics' \
  --test  'curl -sf http://localhost:__HOST_PORT__/metrics | grep -qE "^# (HELP|TYPE) cadvisor_" && curl -sf http://localhost:__HOST_PORT__/metrics | grep -qE "^cadvisor_version_info"' \
  --timeout 20
echo "  ✓ GET /metrics returns Prometheus format with cadvisor_version_info"
