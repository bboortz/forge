#!/usr/bin/env bash
#
# Covers: FG-046 (part d — alertmanager migration from Debian pkg → upstream Go source, 2 binaries)
# CAPs:   build.from-go-source, image.alertmanager-routes-alerts

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=_lib_image_go_stdlib.sh disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh

say()  { printf '\n\033[1;36m[FG-046d]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. Builds with stdlib go1.27+"
bash scripts/build-image.sh alertmanager-scratch-trixie >/dev/null
sv=$(assert_image_go_stdlib_27plus "forge-local/alertmanager-scratch-trixie:0.28" /usr/bin/prometheus-alertmanager)
pass "alertmanager stdlib = ${sv}"

say "2. amtool preserved (built from the same upstream repo)"
docker run --rm --entrypoint=/usr/bin/amtool forge-local/alertmanager-scratch-trixie:0.28 --version >/dev/null 2>&1 \
  || fail "amtool missing or broken"
pass "amtool preserved + runnable"

say "3. Zero Go-stdlib CRITICAL CVEs"
assert_no_stdlib_critical "forge-local/alertmanager-scratch-trixie:0.28"
pass "no stdlib CRITICAL matches"

echo
echo "FG-046d acceptance: all sections passed."
