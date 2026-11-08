#!/usr/bin/env bash
#
# Covers: FG-029
# CAPs:   image.healthy-sidecar, image.no-shell, scan.sbom-embed,
#         build.two-stage-scratch
#
# Validates FG-029: new healthy-scratch-trixie image builds cleanly,
# ships wget + nc + sleep, runs sleep-infinity by default, works as a
# sidecar via shared netns, has no shell, SBOM embedded.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-029]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — image dir + required files
# -----------------------------------------------------------------------------
say "1. images/healthy-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         tests/smoke_binary_runs.sh tests/smoke_cmd_sleeps.sh \
         tests/smoke_sidecar_healthcheck.sh tests/smoke_contents.sh \
         tests/smoke_no_shell.sh tests/smoke_size.sh; do
  test -e "images/healthy-scratch-trixie/${f}" \
    || { echo "  ✗ images/healthy-scratch-trixie/${f} missing" >&2; exit 1; }
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build via scripts/build-image.sh
# -----------------------------------------------------------------------------
say "2. healthy-scratch-trixie builds via scripts/build-image.sh"
if ! docker image inspect forge-local/healthy-scratch-trixie:1 >/dev/null 2>&1; then
  bash scripts/build-image.sh healthy-scratch-trixie >/dev/null
fi
docker image inspect forge-local/healthy-scratch-trixie:1 >/dev/null
pass "forge-local/healthy-scratch-trixie:1 built"

# -----------------------------------------------------------------------------
# Section 3 — per-image smoke suite passes
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
IMAGE_TAG=1 bash images/healthy-scratch-trixie/tests/smoke_binary_runs.sh
IMAGE_TAG=1 bash images/healthy-scratch-trixie/tests/smoke_cmd_sleeps.sh
IMAGE_TAG=1 bash images/healthy-scratch-trixie/tests/smoke_contents.sh
IMAGE_TAG=1 bash images/healthy-scratch-trixie/tests/smoke_no_shell.sh
IMAGE_TAG=1 bash images/healthy-scratch-trixie/tests/smoke_sidecar_healthcheck.sh
IMAGE_TAG=1 bash images/healthy-scratch-trixie/tests/smoke_size.sh
pass "all 6 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — image.yaml declares correct tag + depends_on
# -----------------------------------------------------------------------------
say "4. image.yaml: tag=1, depends_on includes scratch-base-trixie"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' images/healthy-scratch-trixie/image.yaml)
[[ "${tag}" == "1" ]] || { echo "  ✗ image.yaml tag = '${tag}' (want 1)" >&2; exit 1; }
grep -q 'scratch-base-trixie' images/healthy-scratch-trixie/image.yaml \
  || { echo "  ✗ image.yaml missing scratch-base-trixie dep" >&2; exit 1; }
pass "image.yaml correct"

echo
echo "FG-029 acceptance: all sections passed."
