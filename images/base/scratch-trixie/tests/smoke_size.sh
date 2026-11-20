#!/usr/bin/env bash
# Baseline size: enforce a hard 25 MB ceiling (vs. the shared base × 1.1
# fallback). The baseline is intentionally small; derivatives spend their
# size budget on image-specific closure.
#
# Delivers: FG-005 Scenario "baseline image is tiny".
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-25000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-0.2}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
