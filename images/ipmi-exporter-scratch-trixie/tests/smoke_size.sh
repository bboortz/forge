#!/usr/bin/env bash
# Scratch size smoke: ≤ 50 MB absolute ceiling.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-50000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
