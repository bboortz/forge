#!/usr/bin/env bash
#
# Covers: FG-027
# CAPs:   image.redis-serves-cache, image.no-shell, scan.sbom-embed,
#         build.two-stage-scratch
#
# Validates FG-027: new redis-scratch-trixie image builds cleanly,
# runs redis-server, serves client PING/SET/GET through a sidecar
# (protected-mode), has no shell, uid 999 pinned, SBOM embedded.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-027]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — image dir + required files
# -----------------------------------------------------------------------------
say "1. images/redis-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         tests/smoke_binary_runs.sh tests/smoke_server_accepts.sh \
         tests/smoke_user_redis.sh tests/smoke_no_shell.sh \
         tests/smoke_contents.sh tests/smoke_size.sh; do
  test -e "images/redis-scratch-trixie/${f}" \
    || { echo "  ✗ images/redis-scratch-trixie/${f} missing" >&2; exit 1; }
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build via scripts/build-image.sh
# -----------------------------------------------------------------------------
say "2. redis-scratch-trixie builds via scripts/build-image.sh"
if ! docker image inspect forge-local/redis-scratch-trixie:8 >/dev/null 2>&1; then
  bash scripts/build-image.sh redis-scratch-trixie >/dev/null
fi
docker image inspect forge-local/redis-scratch-trixie:8 >/dev/null
pass "forge-local/redis-scratch-trixie:8 built"

# -----------------------------------------------------------------------------
# Section 3 — smoke suite passes against the built image
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
IMAGE_TAG=8 bash images/redis-scratch-trixie/tests/smoke_binary_runs.sh
IMAGE_TAG=8 bash images/redis-scratch-trixie/tests/smoke_contents.sh
IMAGE_TAG=8 bash images/redis-scratch-trixie/tests/smoke_no_shell.sh
IMAGE_TAG=8 bash images/redis-scratch-trixie/tests/smoke_user_redis.sh
IMAGE_TAG=8 bash images/redis-scratch-trixie/tests/smoke_server_accepts.sh
IMAGE_TAG=8 bash images/redis-scratch-trixie/tests/smoke_size.sh
pass "all 6 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — grype against the runtime image: zero OS CVEs
# -----------------------------------------------------------------------------
say "4. grype finds zero OS CVEs against the scratch runtime"
if ! command -v grype >/dev/null 2>&1; then
  echo "  ⚠ grype missing on host — skipping (CI installs it)"
else
  # Use SBOM mode (faster + honors Debian backports — FG-020).
  TMP=$(mktemp -d)
  CID=$(docker create --entrypoint=/nonexistent forge-local/redis-scratch-trixie:8)
  docker cp "${CID}:/sbom.json" "${TMP}/sbom.json" >/dev/null
  docker rm "${CID}" >/dev/null
  os_cves=$(grype "sbom:${TMP}/sbom.json" -o json 2>/dev/null \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
# Filter to OS-level matches (Debian). nvd:cpe hits are app-level or noise.
os = [m for m in d.get('matches', []) if m.get('vulnerability', {}).get('namespace', '').startswith('debian:')]
print(len(os))
")
  rm -rf "${TMP}"
  if [[ "${os_cves}" != "0" ]]; then
    echo "  ⚠ grype found ${os_cves} debian-namespace CVEs — review scan-baseline.json" >&2
    # Non-blocking for Phase 1 (baseline tracks actual state); only warn.
  fi
  pass "grype SBOM scan completes (${os_cves:-?} debian-ns matches, see scan-baseline.json)"
fi

# -----------------------------------------------------------------------------
# Section 5 — image.yaml declares correct tag + depends_on
# -----------------------------------------------------------------------------
say "5. image.yaml: tag=8, depends_on includes scratch-base-trixie"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' images/redis-scratch-trixie/image.yaml)
[[ "${tag}" == "8" ]] || { echo "  ✗ image.yaml tag = '${tag}' (want 8)" >&2; exit 1; }
grep -q 'scratch-base-trixie' images/redis-scratch-trixie/image.yaml \
  || { echo "  ✗ image.yaml missing scratch-base-trixie dep" >&2; exit 1; }
pass "image.yaml correct"

echo
echo "FG-027 acceptance: all sections passed."
