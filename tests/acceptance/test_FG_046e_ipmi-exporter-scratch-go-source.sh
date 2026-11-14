#!/usr/bin/env bash
#
# Covers: FG-046 (part e — ipmi-exporter-scratch dual-builder: forge-builder-go-trixie for the
#         Go exporter + forge-builder-trixie for the Debian freeipmi C deps)
# CAPs:   build.from-go-source, image.ipmi-exporter-serves-metrics

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=_lib_image_go_stdlib.sh disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh

say()  { printf '\n\033[1;36m[FG-046e]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. Builds with stdlib go1.27+ (dual-builder)"
bash scripts/build-image.sh ipmi-exporter-scratch-trixie >/dev/null
sv=$(assert_image_go_stdlib_27plus "forge-local/ipmi-exporter-scratch-trixie:latest" /usr/bin/prometheus-ipmi-exporter)
pass "ipmi-exporter (scratch) stdlib = ${sv}"

say "2. FG-043 collector-override regression guard still green"
IMAGE_TAG=latest bash images/ipmi-exporter-scratch-trixie/tests/smoke_ipmi_collector_uses_elf.sh >/dev/null \
  || fail "collector-override regression guard failed"
pass "ipmi-sensors override still configured"

say "3. Zero Go-stdlib CRITICAL CVEs"
assert_no_stdlib_critical "forge-local/ipmi-exporter-scratch-trixie:latest"
pass "no stdlib CRITICAL matches"

echo
echo "FG-046e acceptance: all sections passed."
