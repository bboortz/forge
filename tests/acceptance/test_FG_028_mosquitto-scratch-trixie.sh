#!/usr/bin/env bash
#
# Covers: FG-028
# CAPs:   image.mosquitto-serves-mqtt, image.no-shell, scan.sbom-embed,
#         build.two-stage-scratch
#
# Validates FG-028: new mosquitto-scratch-trixie image builds cleanly,
# runs mosquitto-server, serves client PUB/SUB via sidecar netns,
# honors password-file auth, has no shell, uid 1883 pinned, SBOM embedded.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-028]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Section 1 — image dir + required files
# -----------------------------------------------------------------------------
say "1. images/mosquitto-scratch-trixie/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml EXPECTATIONS.yaml scan-baseline.json \
         config/mosquitto.conf \
         tests/smoke_binary_runs.sh tests/smoke_server_accepts.sh \
         tests/smoke_password_auth.sh tests/smoke_user_mosquitto.sh \
         tests/smoke_no_shell.sh tests/smoke_contents.sh tests/smoke_size.sh; do
  test -e "images/mosquitto-scratch-trixie/${f}" \
    || { echo "  ✗ images/mosquitto-scratch-trixie/${f} missing" >&2; exit 1; }
done
pass "all required files present"

# -----------------------------------------------------------------------------
# Section 2 — build via scripts/build-image.sh
# -----------------------------------------------------------------------------
say "2. mosquitto-scratch-trixie builds via scripts/build-image.sh"
if ! docker image inspect forge-local/mosquitto-scratch-trixie:2 >/dev/null 2>&1; then
  bash scripts/build-image.sh mosquitto-scratch-trixie >/dev/null
fi
docker image inspect forge-local/mosquitto-scratch-trixie:2 >/dev/null
pass "forge-local/mosquitto-scratch-trixie:2 built"

# -----------------------------------------------------------------------------
# Section 3 — per-image smoke suite passes
# -----------------------------------------------------------------------------
say "3. per-image smoke suite"
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_binary_runs.sh
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_contents.sh
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_no_shell.sh
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_user_mosquitto.sh
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_server_accepts.sh
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_password_auth.sh
IMAGE_TAG=2 bash images/mosquitto-scratch-trixie/tests/smoke_size.sh
pass "all 7 smoke tests green"

# -----------------------------------------------------------------------------
# Section 4 — SIGHUP keeps the broker up (config reload without restart)
# -----------------------------------------------------------------------------
say "4. SIGHUP reloads config; broker stays up"
SERVER="fg028-hup-$$"
trap 'docker rm -f "${SERVER}" >/dev/null 2>&1 || true' RETURN
docker run -d --rm --name "${SERVER}" forge-local/mosquitto-scratch-trixie:2 >/dev/null
sleep 2
# Record container start time, send SIGHUP, confirm the container is still
# the SAME one (same ID, not a restart).
before_id=$(docker inspect --format '{{.Id}}' "${SERVER}")
docker kill --signal=HUP "${SERVER}" >/dev/null
sleep 2
after_id=$(docker inspect --format '{{.Id}}' "${SERVER}" 2>/dev/null || echo "")
if [[ -z "${after_id}" ]]; then
  echo "  ✗ container exited after SIGHUP (should have reloaded and stayed up)" >&2
  exit 1
fi
if [[ "${before_id}" != "${after_id}" ]]; then
  echo "  ✗ container restarted after SIGHUP (different id)" >&2
  exit 1
fi
# Also log must mention "Reloading config"
if ! docker logs "${SERVER}" 2>&1 | grep -qi "reloading config"; then
  echo "  ✗ logs don't mention 'reloading config' after SIGHUP" >&2
  docker logs "${SERVER}" 2>&1 | tail -10 >&2
  exit 1
fi
docker stop -t 2 "${SERVER}" >/dev/null
pass "SIGHUP → config reload, broker stays up"

# -----------------------------------------------------------------------------
# Section 5 — image.yaml declares correct tag + depends_on
# -----------------------------------------------------------------------------
say "5. image.yaml: tag=2, depends_on includes scratch-base-trixie"
tag=$(awk '$1 == "tag:" {gsub(/"/, "", $2); print $2; exit}' images/mosquitto-scratch-trixie/image.yaml)
[[ "${tag}" == "2" ]] || { echo "  ✗ image.yaml tag = '${tag}' (want 2)" >&2; exit 1; }
grep -q 'scratch-base-trixie' images/mosquitto-scratch-trixie/image.yaml \
  || { echo "  ✗ image.yaml missing scratch-base-trixie dep" >&2; exit 1; }
pass "image.yaml correct"

echo
echo "FG-028 acceptance: all sections passed."
