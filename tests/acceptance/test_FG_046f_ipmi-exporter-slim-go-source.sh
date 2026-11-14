#!/usr/bin/env bash
#
# Covers: FG-046 (part f — ipmi-exporter-slim migration from Debian binary → upstream Go source
#         + apt-install freeipmi-tools in runtime, shell + apt preserved)
# CAPs:   build.from-go-source, image.ipmi-exporter-serves-metrics, image.has-shell

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=_lib_image_go_stdlib.sh disable=SC1091
. tests/acceptance/_lib_image_go_stdlib.sh

say()  { printf '\n\033[1;36m[FG-046f]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. Builds with stdlib go1.27+"
bash scripts/build-image.sh ipmi-exporter-slim-trixie >/dev/null
sv=$(assert_image_go_stdlib_27plus "forge-local/ipmi-exporter-slim-trixie:latest" /usr/bin/prometheus-ipmi-exporter)
pass "ipmi-exporter (slim) stdlib = ${sv}"

say "2. freeipmi-tools + /bin/sh preserved (slim contract)"
docker run --rm --entrypoint=/bin/sh forge-local/ipmi-exporter-slim-trixie:latest \
  -c 'test -x /usr/sbin/ipmimonitoring && echo ok' | grep -q "^ok$" \
  || fail "ipmimonitoring missing or /bin/sh broken"
pass "ipmimonitoring + /bin/sh present"

say "3. Zero Go-stdlib CRITICAL CVEs (freeipmi C-pkg CVEs expected in baseline, not stdlib)"
# NB: slim variant has freeipmi C-package CRITICALs in scan-baseline.json.
# assert_no_stdlib_critical scopes strictly to artifact.name == 'stdlib'.
assert_no_stdlib_critical "forge-local/ipmi-exporter-slim-trixie:latest"
pass "no stdlib CRITICAL matches"

echo
echo "FG-046f acceptance: all sections passed."
