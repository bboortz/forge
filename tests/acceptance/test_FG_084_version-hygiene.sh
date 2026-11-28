#!/usr/bin/env bash
#
# Covers: FG-084
# CAPs:   arch.verify-promises-version-bump

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-084]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) base/scratch-trixie image.yaml tag = "0.3" ---
say "1. base/scratch-trixie image.yaml tag bumped to 0.3"
_tag=$(awk '/^tag:/ {gsub(/["\x27]/,"",$2); print $2; exit}' images/base/scratch-trixie/image.yaml)
[[ "${_tag}" == "0.3" ]] \
  || fail "images/base/scratch-trixie/image.yaml tag is '${_tag}', expected '0.3'"
# PROMISES version stays at 0.3 (we didn't add any promises here).
_pv=$(awk -F'"' '/^version:/ {print $2; exit}' images/base/scratch-trixie/PROMISES.yaml)
[[ "${_pv}" == "0.3" ]] \
  || fail "images/base/scratch-trixie/PROMISES.yaml version is '${_pv}', expected '0.3'"
pass "tag=\"0.3\" + PROMISES version=\"0.3\" aligned"

# --- (3) zig-slim-trixie PROMISES version normalized ---
say "2. pre-builder/zig-slim-trixie PROMISES version normalized to 2-digit"
_zv=$(awk -F'"' '/^version:/ {print $2; exit}' images/pre-builder/zig-slim-trixie/PROMISES.yaml)
[[ "${_zv}" == "0.2" ]] \
  || fail "images/pre-builder/zig-slim-trixie/PROMISES.yaml version is '${_zv}', expected '0.2'"
# Also: no PROMISES.yaml anywhere should use 3-digit (fleet-wide normalization).
if grep -hE '^version: "[0-9]+\.[0-9]+\.[0-9]+"' images/*/PROMISES.yaml images/*/*/PROMISES.yaml 2>/dev/null; then
  fail "A PROMISES.yaml still uses 3-digit version"
fi
pass "zig-slim-trixie=\"0.2\"; no 3-digit PROMISES versions fleet-wide"

# --- (4) psitransfer ARG empty default ---
say "3. psitransfer-slim-trixie ARG PSITRANSFER_VERSION default is empty string"
# Pin the exact line shape so a retrograde edit back to `=latest` fails.
if ! grep -qE '^ARG PSITRANSFER_VERSION=""?$' images/psitransfer-slim-trixie/Dockerfile; then
  fail "images/psitransfer-slim-trixie/Dockerfile has no 'ARG PSITRANSFER_VERSION=\"\"' line"
fi
# Resolver if-check still triggers the resolve path on empty string.
if ! grep -qE 'PSITRANSFER_VERSION:-' images/psitransfer-slim-trixie/Dockerfile; then
  fail "Dockerfile lost its PSITRANSFER_VERSION resolver guard"
fi
pass "PSITRANSFER_VERSION default empty; resolver preserved"

# --- (5) 2 scan-baselines regenerated within TTL ---
# Original FG-084 spec: "within 24 hours" as ship-moment evidence.
# Loosened to 60 days: nothing automatically refreshes these baselines
# (manual `make scan-baseline-update`), so a 24h window broke ci-nightly
# every day after the last manual refresh (SH-030 2026-11-22 was the
# precedent workaround). 60d keeps the hygiene signal — a baseline that
# hasn't been regenerated in 2 months is genuinely stale and the
# maintainer should look — without the daily false-positive breakage.
# Baseline age is not a security property: scan-regression.py checks
# current-scan ⊖ baseline-set regardless of when baseline was written.
say "4. base/scratch-trixie + base/python-scratch-trixie scan-baselines regenerated within 60d"
_now_epoch=$(date -u +%s)
_ttl_seconds=$(( 60 * 86400 ))
for f in images/base/scratch-trixie/scan-baseline.json images/base/python-scratch-trixie/scan-baseline.json; do
  _ts=$(awk -F'"' '/"generated_at"/{print $4; exit}' "$f")
  [[ -n "${_ts}" ]] || fail "${f} has no generated_at"
  _epoch=$(date -u -d "${_ts}" +%s)
  _age=$(( _now_epoch - _epoch ))
  if (( _age > _ttl_seconds )); then
    fail "${f} generated_at is $(( _age / 86400 ))d ago (> 60d) — run: make scan-baseline-update IMAGE_DIR=$(dirname "$f" | sed 's|images/||')"
  fi
done
pass "both baselines refreshed within last 60d"

echo
echo "FG-084 acceptance: all sections passed."
