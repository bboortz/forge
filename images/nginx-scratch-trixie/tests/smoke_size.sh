#!/usr/bin/env bash
# Scratch size smoke: enforce the shared base × 1.1 budget (parsed from
# the Dockerfile builder FROM) AND a hard 25 MB absolute ceiling.
#
# Delivers: FG-006 Scenario "nginx image size ≤ 25 MB".
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-25000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-1.26}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
