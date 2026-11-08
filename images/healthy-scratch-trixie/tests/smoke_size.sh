#!/usr/bin/env bash
# Scratch size smoke: hard 30 MB absolute ceiling. GnuTLS + crypto deps
# are the dominant cost; wget + nc + sleep themselves are tiny.
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-30000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-healthy-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-1}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
