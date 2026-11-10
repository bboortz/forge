#!/usr/bin/env bash
#
# Covers: FG-046 (part b — cadvisor migration from golang:X-trixie direct → forge-builder-go-trixie)
# CAPs:   build.from-go-source, image.cadvisor-serves-metrics

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=_lib_image_go_stdlib.sh disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh

say()  { printf '\n\033[1;36m[FG-046b]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. Dockerfile FROMs the shared Go base (not golang:X-trixie direct)"
grep -q "FORGE_BUILDER_GO_REF" images/cadvisor-slim-trixie/Dockerfile \
  || fail "cadvisor Dockerfile doesn't reference FORGE_BUILDER_GO_REF"
if grep -q "ARG GO_BASE=golang" images/cadvisor-slim-trixie/Dockerfile; then
  fail "cadvisor still has ARG GO_BASE=golang (should FROM forge-builder-go-trixie)"
fi
pass "Dockerfile FROMs forge-builder-go-trixie"

say "2. Builds with stdlib go1.27+"
bash scripts/build-image.sh cadvisor-slim-trixie >/dev/null
sv=$(assert_image_go_stdlib_27plus "forge-local/cadvisor-slim-trixie:0.60.6" /usr/bin/cadvisor)
pass "cadvisor stdlib = ${sv}"

say "3. Zero Go-stdlib CRITICAL CVEs"
assert_no_stdlib_critical "forge-local/cadvisor-slim-trixie:0.60.6"
pass "no stdlib CRITICAL matches"

echo
echo "FG-046b acceptance: all sections passed."
