#!/usr/bin/env bash
#
# Covers: FG-046 (part c — node-exporter migration from Debian pkg → upstream Go source)
# CAPs:   build.from-go-source, image.node-exporter-serves-metrics

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=_lib_image_go_stdlib.sh disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh

say()  { printf '\n\033[1;36m[FG-046c]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. Builds with stdlib go1.27+"
bash scripts/build-image.sh node-exporter-scratch-trixie >/dev/null
sv=$(assert_image_go_stdlib_27plus "forge-local/node-exporter-scratch-trixie:1.12" /usr/bin/prometheus-node-exporter)
pass "node-exporter stdlib = ${sv}"

say "2. --version output preserved across migration"
out=$(docker run --rm forge-local/node-exporter-scratch-trixie:1.12 --version 2>&1 | head -1)
echo "${out}" | grep -q "node_exporter, version 1.12.1" \
  || fail "node-exporter --version unexpected: ${out}"
pass "--version preserved: ${out}"

say "3. Zero Go-stdlib CRITICAL CVEs"
assert_no_stdlib_critical "forge-local/node-exporter-scratch-trixie:1.12"
pass "no stdlib CRITICAL matches"

echo
echo "FG-046c acceptance: all sections passed."
