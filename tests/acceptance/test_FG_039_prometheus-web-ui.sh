#!/usr/bin/env bash
#
# Covers: FG-039
# CAPs:   image.prometheus-serves-metrics (EXT)
#
# Validates FG-039: the React UI at `GET /` renders — i.e. no "error
# reading base template" regression. Originally (Debian-packaged image)
# this required shipping /usr/share/prometheus/web/ as a filesystem
# overlay with `cp -r[L]`. FG-048 replaced that mechanism with
# upstream's `-tags builtinassets` which embeds the UI into the Go
# binary via //go:embed; the filesystem overlay is no longer necessary
# and no longer present. What FG-039 CARES ABOUT — the regression
# "GET / returns 500 with 'error reading base template'" — is still
# guarded by smoke_web_ui.sh, which now probes the HTTP surface
# directly rather than inspecting the filesystem.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-039]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — static invariants
# -----------------------------------------------------------------------------
say "1. source files encode the FG-039 contract"

# FG-048: the /usr/share/prometheus/web overlay was removed when the
# Dockerfile switched to from-source with -tags builtinassets (the Go
# binary now carries the UI). The invariant FG-039 enforces — "the UI
# renders at GET / without a base-template error" — is covered by
# smoke_web_ui.sh (HTTP probes) rather than a filesystem assertion.
# Static check: the Dockerfile must be the dual-builder shape AND
# build with builtinassets tag (which is what actually ships the UI
# into the runtime now).
grep -q "builtinassets" images/prometheus-scratch-trixie/Dockerfile \
  || fail "images/prometheus-scratch-trixie/Dockerfile: missing -tags builtinassets (FG-048 embeds the UI into the Go binary)"

test -x images/prometheus-scratch-trixie/tests/smoke_web_ui.sh \
  || fail "images/prometheus-scratch-trixie/tests/smoke_web_ui.sh: missing or not executable"

pass "all static invariants in place (FG-048 shape: -tags builtinassets embeds UI)"

# -----------------------------------------------------------------------------
# Section 2 — build
# -----------------------------------------------------------------------------
say "2. prometheus-scratch-trixie:2.53 builds (with web/ overlay)"
bash scripts/build-image.sh prometheus-scratch-trixie >/dev/null
docker image inspect forge-local/prometheus-scratch-trixie:2.53 >/dev/null
pass "forge-local/prometheus-scratch-trixie:2.53 built"

# -----------------------------------------------------------------------------
# Section 3 — new web UI smoke + FG-035 regression guard
# -----------------------------------------------------------------------------
say "3. web UI smoke + FG-035 regression"
IMAGE_TAG=2.53 bash images/prometheus-scratch-trixie/tests/smoke_web_ui.sh
pass "smoke_web_ui.sh"

# Re-run every FG-035 smoke (except the one we just ran) to catch regressions
# — the only Dockerfile change is adding /usr/share/prometheus/web/ to the
# overlay; nothing else should shift.
for s in images/prometheus-scratch-trixie/tests/smoke_*.sh; do
  [[ "${s}" == *smoke_web_ui.sh ]] && continue
  IMAGE_TAG=2.53 bash "${s}" >/dev/null
done
pass "all existing FG-035 smokes still green"

# -----------------------------------------------------------------------------
# Section 4 — FG-035 acceptance test regression
# -----------------------------------------------------------------------------
say "4. FG-035 acceptance test still green"
bash tests/acceptance/test_FG_035_prometheus-scratch-trixie.sh >/dev/null
pass "test_FG_035_prometheus-scratch-trixie.sh"

echo
echo "FG-039 acceptance: all sections passed."
