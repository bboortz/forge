#!/usr/bin/env bash
# Smoke — /metrics endpoint responds with Prometheus text format.
# Uses scripts/smoke-server.sh for the start-wait-probe-stop harness.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-node-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.12}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 9100 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/metrics' \
  --test  'curl -sf http://localhost:__HOST_PORT__/metrics | grep -qE "^# TYPE node_" && curl -sf http://localhost:__HOST_PORT__/metrics | grep -qE "^node_[a-z_]+_seconds_total"' \
  --timeout 10
echo "  ✓ GET /metrics returns Prometheus text format with node_* metrics"
