#!/usr/bin/env bash
#
# Covers: FG-046 (part a — the shared Go builder base)
# CAPs:   build.shared-go-builder
#
# FG-046's work was split across 6 acceptance tests (a..f) to stay under
# the per-cell CI timeout (FG-038 range invariant [4..10] min). This
# one covers just the shared base image + the prometheus-scratch-trixie
# deferral documentation guard. Each migration has its own test.

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

say "2. prometheus-scratch-trixie migration is deferred (documented, not reverted)"
if ! grep -q "forge-builder-trixie:latest" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile no longer uses forge-builder-trixie — expected to be unchanged (deferred)"
fi
if ! grep -q "install prometheus" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile no longer apt-installs prometheus — expected to be unchanged (deferred)"
fi
if ! grep -q "React UI\|npm" docs/plan/IDEAS.md; then
  fail "IDEAS.md doesn't document the prometheus React-UI-build-pipeline blocker"
fi
pass "prometheus migration deferred + documented in IDEAS.md"

echo
echo "FG-046a acceptance: all sections passed."
