#!/usr/bin/env bash
#
# Covers: FG-040
# CAPs:   image.prometheus-serves-metrics (EXT)
#
# Validates FG-040: prometheus-scratch-trixie:2.53's classic UI
# (/classic/graph) serves EVERY href/src asset with HTTP 200. Prior to
# FG-040, 25 of 34 assets returned 404 (dangling symlinks into
# /usr/share/javascript/ that FG-039's `cp -r` preserved but didn't
# resolve). Fix: `cp -rL` dereferences symlinks so the overlay contains
# real files.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-040]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — Dockerfile dereferences symlinks
# -----------------------------------------------------------------------------
say "1. Dockerfile uses cp -rL for /usr/share/prometheus/web"
grep -qE 'cp -rL /usr/share/prometheus/web ' images/prometheus-scratch-trixie/Dockerfile \
  || fail "images/prometheus-scratch-trixie/Dockerfile: expected cp -rL (dereference symlinks)"
pass "cp -rL present (symlinks dereferenced into overlay)"

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
