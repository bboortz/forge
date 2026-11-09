#!/usr/bin/env bash
# Scratch size smoke: ≤ 300 MB absolute ceiling.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-300000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-2.53}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
