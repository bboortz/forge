#!/usr/bin/env bash
#
# Covers: FG-040
# CAPs:   image.prometheus-serves-metrics (EXT)
#
# Validates FG-040's CONTRACT: every /classic/static/* asset referenced
# from the UI serves HTTP 200 (no dangling symlinks, no 404s).
#
# Historical context: FG-039 shipped /usr/share/prometheus/web via
# `cp -r`, which preserved 25 symlinks pointing at /usr/share/javascript/
# (libjs-bootstrap4, libjs-jquery, libjs-d3, etc.) that were NOT also
# copied. The fix was `cp -rL` to dereference.
#
# FG-048 (2026-11-14) eliminated the filesystem overlay entirely —
# upstream v2.53.x doesn't even expose /classic/* routes (Debian-only
# patch), and the React UI's assets are now embedded in the Go binary
# via -tags builtinassets. What FG-040 *cares* about — "no 404s on the
# UI's asset refs" — is still enforced by smoke_web_ui.sh, which probes
# every href/src in GET / against the running server.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-040]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — FG-048 shape invariant (embedded UI replaces overlay)
# -----------------------------------------------------------------------------
say "1. Dockerfile builds with -tags builtinassets (embeds UI, no filesystem overlay)"
grep -q "builtinassets" images/prometheus-scratch-trixie/Dockerfile \
  || fail "images/prometheus-scratch-trixie/Dockerfile: expected -tags builtinassets (FG-048 replaces the FG-039/040 overlay)"
pass "builtinassets present (UI embedded in Go binary)"

# -----------------------------------------------------------------------------
# Section 2 — build
# -----------------------------------------------------------------------------
say "2. prometheus-scratch-trixie:2.53 builds (with dereferenced static libs)"
bash scripts/build-image.sh prometheus-scratch-trixie >/dev/null
docker image inspect forge-local/prometheus-scratch-trixie:2.53 >/dev/null
pass "forge-local/prometheus-scratch-trixie:2.53 built"

# -----------------------------------------------------------------------------
# Section 3 — extended web UI smoke + FG-035/FG-039 regression
# -----------------------------------------------------------------------------
say "3. extended smoke_web_ui.sh (includes classic-UI asset matrix)"
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_web_ui.sh
pass "smoke_web_ui.sh (incl. every /classic/static/* href/src returns 200)"

# Re-run every other prometheus smoke for regression.
for s in images/prometheus-scratch-trixie/tests/smoke_*.sh; do
  [[ "${s}" == *smoke_web_ui.sh ]] && continue
  IMAGE_TAG=2.53 bash "${s}" >/dev/null
done
pass "all other prometheus smokes still green"

# -----------------------------------------------------------------------------
# Section 4 — FG-035 + FG-039 acceptance regression
# -----------------------------------------------------------------------------
say "4. FG-035 + FG-039 acceptance still green"
bash tests/acceptance/test_FG_035_prometheus-scratch-trixie.sh >/dev/null
pass "test_FG_035_prometheus-scratch-trixie.sh"
bash tests/acceptance/test_FG_039_prometheus-web-ui.sh >/dev/null
pass "test_FG_039_prometheus-web-ui.sh"

echo
echo "FG-040 acceptance: all sections passed."
