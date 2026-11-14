#!/usr/bin/env bash
# Slim size smoke: ≤ 150 MB absolute ceiling.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-150000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-cadvisor-slim-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
