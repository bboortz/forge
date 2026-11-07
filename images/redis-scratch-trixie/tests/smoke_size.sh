#!/usr/bin/env bash
# Scratch size smoke: enforce the shared base × 1.1 budget AND a hard
# 150 MB absolute ceiling. Redis is small — jemalloc + glibc + redis
# binaries + a few MB of overlay libs.
#
# Delivers: FG-007 Scenario "redis-scratch image fits under 50 MB".
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-50000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-redis-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-8}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
