#!/usr/bin/env bash
# Scratch size smoke: enforce the shared base × 1.1 budget AND a hard
# 150 MB absolute ceiling. Postgres is large — libicu alone is ~30 MB,
# shared data another 30 MB, binaries + libs the rest.
#
# Delivers: FG-007 Scenario "postgres-scratch image fits under 150 MB".
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-150000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-17}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
