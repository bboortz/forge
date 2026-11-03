#!/usr/bin/env bash
# Scratch size smoke: enforce the shared base × 1.1 budget (parsed from the
# Dockerfile builder FROM) AND a hard 60 MB absolute ceiling.
#
# Delivers: FG-002 Scenario "Image size is within budget (base × 1.1)" +
#           FG-003 Scenario "Scratch image fits under 60 MB".
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-60000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-python}"
export IMAGE_TAG="${IMAGE_TAG:-3.13-scratch-trixie}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
