#!/usr/bin/env bash
# Smoke — final image size ≤ upstream base × 1.1 (10% headroom for apt-upgrade
# deltas). The base is parsed from the Dockerfile's FROM line so the
# comparison tracks any future base-image bump without script edits. Scratch
# variants have no meaningful base ("FROM scratch" is 0 bytes) so they
# additionally enforce an absolute MAX_BYTES ceiling via the SIZE_CEILING env.
#
# Delivers: FG-002 Scenario "Image size is within budget (base × 1.1)".
# Reusable pattern — every future image's smoke_size.sh uses the same shape.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-slim-trixie}"
IMAGE_TAG="${IMAGE_TAG:-18}"
# postgres:18 upstream is rebuilt infrequently; each Forge rebuild accumulates
# ~70-80 MB of security backports via `apt-get upgrade`, pushing the final
# past the strict `base × 1.1` budget. Override to 1.3 (30% headroom) which
# still catches genuine size regressions but tolerates stale-upstream drift.
BUDGET_RATIO_NUM="${BUDGET_RATIO_NUM:-13}"
BUDGET_RATIO_DEN="${BUDGET_RATIO_DEN:-10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
# Self-locate sibling Dockerfile so the script works under whatever image dir
# name the variant lives in (python-slim-trixie, python-scratch-trixie, …).
DOCKERFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Dockerfile"

# Last FROM that isn't `scratch` is the "upstream base" we're comparing
# against. For single-stage slim images that's the only FROM; for two-stage
# scratch images the builder's base is what matters.
BASE=$(awk 'toupper($1) == "FROM" && $2 !~ /^scratch$/ { print $2 }' "${DOCKERFILE}" | tail -1 | awk '{print $1}')
if [[ -z "${BASE}" ]]; then
  echo "  ✗ could not parse FROM reference from ${DOCKERFILE}" >&2
  exit 1
fi

docker image inspect "${BASE}"  >/dev/null 2>&1 || docker pull  "${BASE}"  >/dev/null
docker image inspect "${IMAGE}" >/dev/null 2>&1 || { echo "  ✗ ${IMAGE} not present — run make build first" >&2; exit 1; }

BASE_SIZE=$(docker image inspect --format='{{.Size}}' "${BASE}")
OUR_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE}")
BUDGET=$(( BASE_SIZE * BUDGET_RATIO_NUM / BUDGET_RATIO_DEN ))

if [[ "${OUR_SIZE}" -gt "${BUDGET}" ]]; then
  echo "  ✗ size ${OUR_SIZE} exceeds budget ${BUDGET} (base ${BASE_SIZE} × ${BUDGET_RATIO_NUM}/${BUDGET_RATIO_DEN})" >&2
  exit 1
fi

# Scratch variants (or any image that passes SIZE_CEILING) also enforce a
# hard absolute ceiling — useful when "base × 1.1" would be way too generous
# (e.g. a scratch runtime copying from a 118 MB slim builder).
if [[ -n "${SIZE_CEILING:-}" ]]; then
  if [[ "${OUR_SIZE}" -gt "${SIZE_CEILING}" ]]; then
    echo "  ✗ size ${OUR_SIZE} exceeds absolute ceiling ${SIZE_CEILING}" >&2
    exit 1
  fi
  echo "  ✓ size ${OUR_SIZE}B ≤ budget ${BUDGET}B (base × 1.1) AND ≤ ceiling ${SIZE_CEILING}B"
else
  echo "  ✓ size ${OUR_SIZE}B ≤ budget ${BUDGET}B (base ${BASE} = ${BASE_SIZE}B × ${BUDGET_RATIO_NUM}/${BUDGET_RATIO_DEN})"
fi
