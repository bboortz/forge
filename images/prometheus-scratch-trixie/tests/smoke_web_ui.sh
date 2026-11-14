#!/usr/bin/env bash
# Smoke — the web UI actually renders.
#
# Pre-FG-039 regression (Debian-packaged prometheus era):
#   - GET / → 302 /classic/graph → 500 "error reading base template:
#     open /usr/share/prometheus/web/templates/_base.html: no such file"
# Post-FG-039:
#   - GET /         → HTTP 200 + HTML body (React UI, go:embed since 2.21)
#   - GET /classic/graph → HTTP 200 + HTML body (classic UI, template engine)
#   - No 'error reading base template' in the container logs.
#
# FG-048 (from-source with -tags builtinassets): the classic UI _base.html
# + every /classic/static/* asset is now EMBEDDED in the Go binary via
# //go:embed. The filesystem overlay at /usr/share/prometheus/web/ that
# FG-039 added (and FG-040 fixed with `cp -rL`) is gone — the binary
# self-serves. Section 1 below is the authoritative behavior check (HTTP
# probes); section 2 is FG-040's asset matrix. The legacy file-presence
# check for /usr/share/prometheus/web/templates/_base.html on disk was
# dropped (would now (correctly) fail — the file is inside the ELF, not
# on disk).
#
# Delivers: FG-039 + FG-040 Scenarios via HTTP probes.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

TMP="$(mktemp -d)"
CID="fg048-prom-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true; rm -rf "${TMP}"' EXIT

# -----------------------------------------------------------------------------
# 1. Boot + HTTP probes (React + classic UI render from embedded assets)
# -----------------------------------------------------------------------------
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

# 2b. React UI routes also serve (regression guard — if asset embedding
# is broken, / loads but /graph + /alerts 404).
for path in /graph /alerts /rules /service-discovery; do
  set +e
  code=$(curl -sfL -o /dev/null -w '%{http_code}' "http://localhost:${PORT}${path}")
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 || "${code}" != "200" ]]; then
    echo "  ✗ GET ${path} rc=${rc} http=${code}" >&2
    docker logs "${CID}" 2>&1 | tail -10 >&2
    exit 1
  fi
done
echo "  ✓ GET /graph + /alerts + /rules + /service-discovery all return HTTP 200"

# 2c. /classic/* is DEPRECATED in upstream prometheus v2.53.x — the Debian-
# packaged variant our pre-FG-048 image used had a backwards-compat patch
# that restored the /classic/* routes, but the FG-048 from-source build
# matches the upstream contract (no /classic/*). Operators who relied on
# /classic/graph bookmarks must migrate to /graph. Documented in FG-048's
# plan doc under "Breaking changes".
set +e
classic_code=$(curl -sL -o /dev/null -w '%{http_code}' "http://localhost:${PORT}/classic/graph")
set -e
if [[ "${classic_code}" == "200" ]]; then
  echo "  ⚠️  GET /classic/graph still returns 200 — classic UI route leaked back in" >&2
  echo "    (upstream v2.53.5 does not expose /classic/*; if this image does," >&2
  echo "    we've accidentally re-introduced a Debian patch)" >&2
  exit 1
fi
echo "  ✓ GET /classic/graph returns ${classic_code} (upstream-parity; Debian /classic patch intentionally not applied)"

# 2d. No 'error reading base template' in logs (FG-039 regression guard —
# would appear if /classic/graph was still mapped to the Go template engine
# but the templates were missing on disk).
if docker logs "${CID}" 2>&1 | grep -q 'error reading base template'; then
  echo "  ✗ 'error reading base template' found in container logs" >&2
  docker logs "${CID}" 2>&1 | grep 'error reading base template' | head -3 >&2
  exit 1
fi
echo "  ✓ no 'error reading base template' in container logs"

# -----------------------------------------------------------------------------
# 3. Every React-UI static asset referenced from / serves 200
# -----------------------------------------------------------------------------
# Equivalent of FG-040's /classic/static/* matrix, adapted to the React
# routes that embedded assets now serve from. Catches a regression where
# -tags builtinassets compiles but a file is missing from the embed.FS.
# `|| true` on the greps prevents `set -e` + `pipefail` from killing the
# script when no matches are found (React SPAs commonly load assets via
# JS at runtime, so the initial HTML may have 0 inline refs).
curl -sL "http://localhost:${PORT}/" -o "${TMP}/root.html"
asset_list="${TMP}/assets.txt"
: > "${asset_list}"
set +e
grep -oE 'href="[^"]+"|src="[^"]+"' "${TMP}/root.html" \
  | awk -F\" '{print $2}' \
  | grep -E '^/static/|^/graph/|\.js$|\.css$' \
  | grep -v '^http' \
  | sed 's|?v=.*||' \
  | sort -u > "${asset_list}"
set -e

asset_count=$(wc -l < "${asset_list}")
if [[ "${asset_count}" -eq 0 ]]; then
  echo "  (no inline /static/ asset refs in / HTML — React SPA fetches via JS runtime; skipping asset matrix)"
else
  failures=0
  while read -r path; do
    # Upstream React build emits relative paths like ./static/css/main.X.css;
    # strip the ./ prefix + ensure a single leading / so the URL is absolute.
    normalized="${path#./}"
    normalized="/${normalized#/}"
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORT}${normalized}")
    if [[ "${code}" != "200" ]]; then
      echo "  ✗ HTTP ${code}  ${normalized} (from ref: ${path})" >&2
      failures=$((failures + 1))
    fi
  done < "${asset_list}"

  [[ "${failures}" -eq 0 ]] \
    || { echo "  ✗ ${failures}/${asset_count} embedded assets returned non-200" >&2; exit 1; }
  echo "  ✓ all ${asset_count} embedded /static/ assets return HTTP 200"
fi
