#!/usr/bin/env bash
# Smoke — /metrics responds even without /dev/ipmi0.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

bash "${ROOT}/scripts/smoke-server.sh" \
  --image "${IMAGE}" \
  --port 9290 \
  --ready 'curl -sf -o /dev/null http://localhost:__HOST_PORT__/metrics' \
  --test  'curl -sf http://localhost:__HOST_PORT__/metrics | grep -qE "^# (HELP|TYPE) ipmi_" && curl -sf http://localhost:__HOST_PORT__/metrics | grep -qE "^ipmi_scrape_duration_seconds"' \
  --timeout 10
echo "  ✓ GET /metrics returns Prometheus format with ipmi_* self-metrics"
