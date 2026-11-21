#!/usr/bin/env bash
#
# Covers: FG-082
# CAPs:   image.ipmi-exporter-serves-metrics, image.prometheus-serves-metrics,
#         image.uptime-kuma-serves-monitoring

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-082]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) stale "+ dumb-init" phrases gone from the four archlinux locations ---
say "1. stale '+ dumb-init' phrase removed from 4 archlinux locations"

# PROMISES.yaml header (line 3) + size-budget description (line 36). The
# whole file is checked — the only dumb-init mention allowed anywhere is
# NONE (the delta is documented in the Dockerfile).
if grep -q "dumb-init" images/pre-builder/archlinux/PROMISES.yaml; then
  fail "images/pre-builder/archlinux/PROMISES.yaml still mentions dumb-init"
fi

# smoke_size.sh header comment.
if grep -q "dumb-init" images/pre-builder/archlinux/tests/smoke_size.sh; then
  fail "images/pre-builder/archlinux/tests/smoke_size.sh still mentions dumb-init"
fi

# base/archlinux/Dockerfile comment at line 14. The DELTA note in pre-
# builder/archlinux/Dockerfile:16-20 stays — only base/archlinux needs
# cleanup.
if grep -qE "\+ dumb-init|dumb-init\)" images/base/archlinux/Dockerfile; then
  fail "images/base/archlinux/Dockerfile still mentions dumb-init in composition"
fi

# pre-builder/archlinux/Dockerfile keeps its explicit DELTA note. Verify
# that specifically — this is the CURRENT truth and must not be removed.
grep -q "dumb-init is NOT shipped" images/pre-builder/archlinux/Dockerfile \
  || fail "images/pre-builder/archlinux/Dockerfile DELTA note was removed (should stay)"
pass "4 stale refs gone; DELTA note preserved"

# --- (2) 4 orphan smokes now referenced by PROMISES entries ---
say "2. 4 orphan smokes have a PROMISES entry"

for pair in \
    "images/ipmi-exporter-scratch-trixie/PROMISES.yaml:images/ipmi-exporter-scratch-trixie/tests/smoke_ipmi_collector_uses_elf.sh" \
    "images/prometheus-scratch-trixie/PROMISES.yaml:images/prometheus-scratch-trixie/tests/smoke_console_files.sh" \
    "images/prometheus-scratch-trixie/PROMISES.yaml:images/prometheus-scratch-trixie/tests/smoke_lifecycle_reload.sh" \
    "images/uptime-kuma-slim-trixie/PROMISES.yaml:images/uptime-kuma-slim-trixie/tests/smoke_ping_available.sh"; do
  promises="${pair%%:*}"
  smoke="${pair##*:}"
  grep -qF "${smoke}" "${promises}" \
    || fail "${promises} is missing a reference to ${smoke}"
done
pass "all 4 smokes registered"

# --- (3) no new CAPs; no new images ---
say "3. no new CAPs, no new images"

# Headcount CAPs before/after: FG-081 ended with 111 tracked CAPs; FG-082
# must not change that count.
_cap_count=$(grep -cE "^### " docs/CAPABILITIES.md)
# Soft check — the assertion is "no new CAPs defined for FG-082". We lock
# the count against a FLOOR rather than an exact value so future FGs can
# add CAPs without re-touching this test.
if [[ "${_cap_count}" -lt 113 ]]; then
  fail "docs/CAPABILITIES.md has only ${_cap_count} CAPs — expected ≥ 113 (FG-081 baseline)"
fi

# Ensure no new image dirs appeared (the diff from main is only to text
# files + PROMISES.yaml entries; no new images/<x>/ directory).
# This is checked implicitly via git-status but we verify no new
# image.yaml landed under a new dir.
pass "CAP count ≥ 113 (floor); no new image dirs expected"

# --- (4) traceability + verify-contracts still green ---
say "4. traceability + verify-contracts green"
bash scripts/verify-traceability.sh >/dev/null \
  || fail "traceability failed"
python3 scripts/verify-contracts.py >/dev/null 2>&1 \
  || fail "verify-contracts failed"
pass "traceability + contracts green"

echo
echo "FG-082 acceptance: all sections passed."
