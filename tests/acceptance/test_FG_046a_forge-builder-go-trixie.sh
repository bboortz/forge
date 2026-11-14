#!/usr/bin/env bash
#
# Covers: FG-046 (part a — the shared Go builder base)
# CAPs:   build.shared-go-builder
#
# FG-046's work was split across 6 acceptance tests (a..f) to stay under
# the per-cell CI timeout (FG-038 range invariant [4..10] min). This
# one covers just the shared base image + a now-shipped-follow-up guard:
# originally FG-046 DEFERRED prometheus-scratch-trixie (the one Go image
# it couldn't migrate without a Node UI build pipeline). FG-048 shipped
# that migration (dual-builder with forge-builder-node-trixie). This
# test now guards the post-FG-048 shape instead of the deferral.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-046a]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. forge-builder-go-trixie:0.1 builds + smokes pass"
bash scripts/build-image.sh forge-builder-go-trixie >/dev/null
for s in images/forge-builder-go-trixie/tests/smoke_*.sh; do
  bash "${s}" >/dev/null
done
pass "forge-builder-go-trixie:0.1 built + 5 smokes green"

say "2. prometheus-scratch-trixie now migrated to from-source (FG-048 shipped)"
if ! grep -q "FORGE_BUILDER_GO_REF" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile should FROM forge-builder-go-trixie (FG-048 dual-builder)"
fi
if ! grep -q "FORGE_BUILDER_NODE_REF" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile should also FROM forge-builder-node-trixie (FG-048 UI builder)"
fi
if ! grep -q "builtinassets" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile should use -tags builtinassets (FG-048 embedded UI)"
fi
if grep -q "install prometheus" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile should NOT apt-install the prometheus package (FG-048 builds from source)"
fi
pass "prometheus-scratch-trixie dual-builder shape (FG-048) in place"
