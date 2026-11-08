#!/usr/bin/env bash
#
# Covers: FG-031
# CAPs:   image.hc-embedded, image.nginx-serves-http, image.python-scratch-nonroot
#
# Validates FG-031: nginx-scratch-trixie + python-scratch-trixie carry /hc
# so docker-native healthchecks replace the FG-030 sidecar companion
# container pattern. nginx also bakes a HEALTHCHECK on /healthz.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-031]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — static source invariants
# -----------------------------------------------------------------------------
say "1. source files encode the FG-031 contract"

# Both Dockerfiles reference an hc stage.
for d in nginx-scratch-trixie python-scratch-trixie; do
  # shellcheck disable=SC2016  # intentional literal ${HC_REF} match in grep pattern
  grep -qE '^ARG HC_REF='           "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing ARG HC_REF"
  # shellcheck disable=SC2016
  grep -qE '^FROM \$\{HC_REF\} AS hc' "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing FROM \${HC_REF} AS hc stage"
  grep -qE 'COPY --from=hc /hc /hc' "images/${d}/Dockerfile" \
    || fail "images/${d}/Dockerfile: missing COPY --from=hc /hc /hc"
done

# nginx bakes HEALTHCHECK; python deliberately does NOT.
grep -qE '^HEALTHCHECK ' images/nginx-scratch-trixie/Dockerfile \
  || fail "nginx-scratch-trixie/Dockerfile: expected HEALTHCHECK instruction"
if grep -qE '^HEALTHCHECK ' images/python-scratch-trixie/Dockerfile; then
  fail "python-scratch-trixie/Dockerfile: HEALTHCHECK must NOT be baked (consumer-decided)"
fi

# nginx.conf has /healthz handler.
grep -qE 'location = /healthz' images/nginx-scratch-trixie/nginx.conf \
  || fail "nginx.conf: missing /healthz location block"

# PROMISES.yaml carries runtime.hc-binary for both images.
for d in nginx-scratch-trixie python-scratch-trixie; do
  grep -q 'runtime.hc-binary' "images/${d}/PROMISES.yaml" \
    || fail "images/${d}/PROMISES.yaml: missing promise runtime.hc-binary"
done

pass "source invariants in place"

# -----------------------------------------------------------------------------
# Section 2 — build both images
# -----------------------------------------------------------------------------
say "2. build nginx-scratch-trixie + python-scratch-trixie"
for d in nginx-scratch-trixie python-scratch-trixie; do
  bash scripts/build-image.sh "${d}" >/dev/null
done
docker image inspect forge-local/nginx-scratch-trixie:1.26 >/dev/null
docker image inspect forge-local/python-scratch-trixie:3.14 >/dev/null
pass "both images built"

# -----------------------------------------------------------------------------
# Section 3 — nginx: /hc baked + HEALTHCHECK present + auto-healthy
# -----------------------------------------------------------------------------
say "3. nginx: in-image healthcheck via /hc on /healthz"

hc_test="$(docker inspect --format '{{json .Config.Healthcheck.Test}}' \
             forge-local/nginx-scratch-trixie:1.26)"
case "${hc_test}" in
  *'/hc'*'/healthz'*) pass "HEALTHCHECK references /hc + /healthz" ;;
  *) fail "docker inspect Healthcheck.Test unexpected: ${hc_test}" ;;
esac

IMAGE_TAG=1.26 bash images/nginx-scratch-trixie/tests/smoke_hc_healthcheck.sh
pass "smoke_hc_healthcheck.sh"

# -----------------------------------------------------------------------------
# Section 4 — python: /hc baked, no HEALTHCHECK, /hc runnable
# -----------------------------------------------------------------------------
say "4. python: /hc present, no HEALTHCHECK"
py_hc="$(docker inspect --format '{{json .Config.Healthcheck}}' \
           forge-local/python-scratch-trixie:3.14)"
# docker returns "null" for an unset Healthcheck.
case "${py_hc}" in
  null) pass "python-scratch-trixie has no baked HEALTHCHECK" ;;
  *) fail "python-scratch-trixie should have no HEALTHCHECK, got: ${py_hc}" ;;
esac

IMAGE_NAME=python-scratch-trixie IMAGE_TAG=3.14 \
  bash images/python-scratch-trixie/tests/smoke_hc_present.sh
pass "smoke_hc_present.sh"

# -----------------------------------------------------------------------------
# Section 5 — no size regression (budgets already enforced by smoke_size.sh)
# -----------------------------------------------------------------------------
say "5. existing size smokes stay green with hc embedded"
IMAGE_TAG=1.26 bash images/nginx-scratch-trixie/tests/smoke_size.sh
IMAGE_NAME=python-scratch-trixie IMAGE_TAG=3.14 \
  bash images/python-scratch-trixie/tests/smoke_size.sh
pass "both size budgets respected"

echo
echo "FG-031 acceptance: all sections passed."
