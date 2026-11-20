#!/usr/bin/env bash
# Scratch size smoke: ≤ 100 MB absolute ceiling.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-100000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-alertmanager-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../pre-builder/python-slim-trixie/tests" && pwd)/smoke_size.sh"
