#!/usr/bin/env bash
# FG-064 — Render the mermaid block inside docs/specs/image-dependency-graph.md
# to docs/specs/image-dependency-graph.svg via the mermaid-cli Docker image.
#
# Docker-based so forge contributors don't need to install node + puppeteer
# locally. Version pinning keeps output reproducible for the drift gate.
#
# Gracefully no-ops (with a warning) if Docker isn't available — pre-commit
# won't block contributors on Docker-less machines. CI always has Docker so
# the drift gate still fires there.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

MERMAID_CLI_IMAGE="${FORGE_MERMAID_CLI_IMAGE:-minlag/mermaid-cli:11.4.2}"
SRC_MD="docs/specs/image-dependency-graph.md"
OUT_SVG="docs/specs/image-dependency-graph.svg"
STAGE_MMD=".make/dep-graph.mmd"

# Docker daemon reachable? Graceful no-op otherwise.
if ! command -v docker >/dev/null 2>&1; then
  echo "mermaid-to-svg: docker not installed — skipping SVG regen (CI will catch any drift)." >&2
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "mermaid-to-svg: docker daemon unreachable — skipping SVG regen (CI will catch any drift)." >&2
  exit 0
fi

# Extract the mermaid block from inside the GENERATED markers.
mkdir -p "$(dirname "${STAGE_MMD}")"
# shellcheck disable=SC2064  # intentional eval-now; STAGE_MMD is stable here
trap "rm -f '${STAGE_MMD}'" EXIT

awk '
  /<!-- GENERATED:dep-graph START/   { in_gen=1; next }
  /<!-- GENERATED:dep-graph END -->/ { in_gen=0 }
  in_gen && /^```mermaid$/ { in_m=1; next }
  in_gen && in_m && /^```$/ { in_m=0; next }
  in_gen && in_m { print }
' "${SRC_MD}" > "${STAGE_MMD}"

if [[ ! -s "${STAGE_MMD}" ]]; then
  echo "mermaid-to-svg: no mermaid block found between GENERATED markers in ${SRC_MD}" >&2
  exit 2
fi

# Render. mermaid-cli reads the .mmd file inside the mounted repo and
# writes the .svg next to it. Pin the image tag so output is byte-stable.
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$(pwd):/data" \
  -w /data \
  "${MERMAID_CLI_IMAGE}" \
  -i "${STAGE_MMD}" -o "${OUT_SVG}" \
  -b transparent \
  --quiet

echo "✓ wrote ${OUT_SVG} ($(wc -c < "${OUT_SVG}") bytes)"
