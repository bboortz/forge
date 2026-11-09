#!/usr/bin/env bash
# Smoke — the web UI actually renders.
#
# Pre-FG-039 regression:
#   - GET / → 302 /classic/graph → 500 "error reading base template:
#     open /usr/share/prometheus/web/templates/_base.html: no such file"
# Post-FG-039:
#   - GET /         → HTTP 200 + HTML body (React UI, go:embed since 2.21)
#   - GET /classic/graph → HTTP 200 + HTML body (classic UI, template engine)
#   - No 'error reading base template' in the container logs.
#
# Delivers: FG-039 Scenarios "React UI loads at /", "Classic UI renders
# without template errors", "web/ asset dir shipped".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# -----------------------------------------------------------------------------
# 1. File presence — _base.html actually in the image
# -----------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
docker save "${IMAGE}" -o "${TMP}/i.tar"
tar -xf "${TMP}/i.tar" -C "${TMP}" manifest.json
mapfile -t layers < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for L in m[0]["Layers"]:
    print(L)
' "${TMP}/manifest.json")

found=0
for L in "${layers[@]}"; do
  tar -xf "${TMP}/i.tar" -C "${TMP}" "${L}"
  c=$(tar -tf "${TMP}/${L}" 2>/dev/null \
      | grep -cE '(^|/)usr/share/prometheus/web/templates/_base\.html$' || true)
  [[ "${c}" -ge 1 ]] && found=1
done
[[ "${found}" -eq 1 ]] \
  || { echo "  ✗ /usr/share/prometheus/web/templates/_base.html missing from image" >&2; exit 1; }
echo "  ✓ /usr/share/prometheus/web/templates/_base.html present in image"

# -----------------------------------------------------------------------------
# 2. Boot + HTTP probes
# -----------------------------------------------------------------------------
CID="fg039-prom-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true; rm -rf "${TMP}"' EXIT
docker run -d --rm --name "${CID}" -p 0:9090 "${IMAGE}" >/dev/null

PORT=$(docker port "${CID}" 9090/tcp | head -1 | awk -F: '{print $NF}')
[[ -n "${PORT}" ]] || { echo "  ✗ could not resolve host port" >&2; exit 1; }

# Wait for /-/healthy before probing UI.
deadline=$(( $(date +%s) + 20 ))
until curl -sf -o /dev/null "http://localhost:${PORT}/-/healthy" 2>/dev/null; do
  (( $(date +%s) < deadline )) || { echo "  ✗ /-/healthy timed out" >&2; exit 1; }
  sleep 0.5
done

# 2a. React UI at /
set +e
root_code=$(curl -sfL -o "${TMP}/root.html" -w '%{http_code}' "http://localhost:${PORT}/")
rc=$?
set -e
if [[ "${rc}" -ne 0 || "${root_code}" != "200" ]]; then
  echo "  ✗ GET / rc=${rc} http=${root_code}" >&2
  docker logs "${CID}" 2>&1 | tail -10 >&2
  exit 1
fi
if ! grep -qiE '<html|<!doctype' "${TMP}/root.html"; then
  echo "  ✗ GET / body is not HTML" >&2
  head -c 200 "${TMP}/root.html" >&2 || true
  exit 1
fi
echo "  ✓ GET / returns HTTP 200 + HTML (React UI)"

# 2b. Classic UI at /classic/graph
set +e
classic_code=$(curl -sfL -o "${TMP}/classic.html" -w '%{http_code}' \
  "http://localhost:${PORT}/classic/graph")
rc=$?
set -e
if [[ "${rc}" -ne 0 || "${classic_code}" != "200" ]]; then
  echo "  ✗ GET /classic/graph rc=${rc} http=${classic_code}" >&2
  docker logs "${CID}" 2>&1 | tail -10 >&2
  exit 1
fi
if ! grep -qiE '<html' "${TMP}/classic.html"; then
  echo "  ✗ GET /classic/graph body is not HTML" >&2
  head -c 200 "${TMP}/classic.html" >&2 || true
  exit 1
fi
echo "  ✓ GET /classic/graph returns HTTP 200 + HTML"

# 2c. Logs must NOT contain the base-template error
if docker logs "${CID}" 2>&1 | grep -q 'error reading base template'; then
  echo "  ✗ 'error reading base template' found in container logs" >&2
  docker logs "${CID}" 2>&1 | grep 'error reading base template' | head -3 >&2
  exit 1
fi
echo "  ✓ no 'error reading base template' in container logs"
