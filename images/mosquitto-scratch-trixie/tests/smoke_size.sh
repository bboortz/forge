#!/usr/bin/env bash
# Scratch size smoke: hard 30 MB absolute ceiling. Mosquitto is tiny
# (binary + ~5 overlay libs + default config).
set -euo pipefail

SIZE_CEILING=${SIZE_CEILING:-30000000}
export SIZE_CEILING
export IMAGE_NAME="${IMAGE_NAME:-mosquitto-scratch-trixie}"
export IMAGE_TAG="${IMAGE_TAG:-2}"
export REGISTRY="${REGISTRY:-forge-local}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python-slim-trixie/tests" && pwd)/smoke_size.sh"
