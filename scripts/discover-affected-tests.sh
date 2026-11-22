#!/usr/bin/env bash
# FG-090 / SH-022 — emit a scoped GHA matrix for the acceptance tests.
#
# Wraps `smart-check.sh --dry-run` (FG-017) to decide dispatch shape:
#   DISPATCH=full …              → full matrix (same as discover-tests.sh)
#   DISPATCH=test-fast-only      → empty matrix (lint-verify covers it)
#   DISPATCH=scoped … images=…   → scoped matrix: tests that mention any
#                                   affected image name + framework tests
#                                   (tests that don't reference any
#                                    specific image dir).
#
# Output on stdout matches discover-tests.sh shape:
#   {"include":[{"test":"<path>","fg_id":"FG-NNN"},...]}
#
# Fail-safe: any error or unexpected dispatch line → full matrix.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TESTS_DIR="tests/acceptance"
IMAGES_DIR="images"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

emit_matrix_from_test_list() {
  # $1: newline-separated list of test files (full paths).
  local tests="$1"
  local first=1
  printf '{"include":['
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    base=$(basename "$t")
    if [[ "$base" =~ ^test_FG_([0-9]{3})([a-z]?)_ ]]; then
      fg_id="FG-${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    else
      continue
    fi
    [ "$first" = 1 ] || printf ','
    printf '{"test":"%s","fg_id":"%s"}' "$t" "$fg_id"
    first=0
  done <<< "$tests"
  printf ']}'
  echo
}

emit_full() { bash scripts/discover-tests.sh; }

emit_empty() { printf '{"include":[]}\n'; }

emit_scoped() {
  # $1: space-separated list of affected image dir names (may contain nested
  #     paths like "base/python-scratch-trixie" or flat "nginx-scratch-trixie").
  local images_csv="$1"
  [ -n "$images_csv" ] || { emit_full; return; }

  # Build a list of unique image name tokens for grep. Split both flat and
  # nested forms (base/python-scratch-trixie → both "base/python-scratch-
  # trixie" AND "python-scratch-trixie") so tests that reference either
  # form match.
  local tokens=()
  for img in $images_csv; do
    tokens+=("$img")
    if [[ "$img" == */* ]]; then
      tokens+=("${img#*/}")
    fi
  done

  # Scoped tests: any test file whose body or filename mentions an
  # affected image token.
  local scoped_tests=""
  for tok in "${tokens[@]}"; do
    [ -n "$tok" ] || continue
    matches=$(grep -l -F -- "$tok" "$TESTS_DIR"/test_FG_*.sh 2>/dev/null || true)
    [ -n "$matches" ] && scoped_tests+="$matches"$'\n'
  done

  # Framework tests: tests whose body references NO `images/` path at all.
  # These are repo-wide invariants (CAP traceability, docs layout, pre-push
  # smoke, etc.) — always run to catch structural regressions.
  local framework_tests=""
  for t in "$TESTS_DIR"/test_FG_*.sh; do
    [ -f "$t" ] || continue
    if ! grep -q -F "images/" "$t" 2>/dev/null; then
      framework_tests+="$t"$'\n'
    fi
  done

  # Union + sort + dedupe.
  local combined
  combined=$(printf '%s%s' "$scoped_tests" "$framework_tests" | sort -u | grep . || true)

  if [ -z "$combined" ]; then
    # Scoped yielded nothing (very narrow diff) — fall back to full matrix
    # for safety. Dev-cycle-doc §"Design rule": nothing silently skipped.
    emit_full
    return
  fi

  emit_matrix_from_test_list "$combined"
}

# ---------------------------------------------------------------------------
# Main: ask smart-check what to do.
# ---------------------------------------------------------------------------

dispatch_line=$(SMART_CHECK_DRY_RUN=1 bash scripts/smart-check.sh 2>&1 | grep '^DISPATCH=' | tail -1 || true)

case "$dispatch_line" in
  DISPATCH=full*)
    emit_full
    ;;
  DISPATCH=test-fast-only)
    emit_empty
    ;;
  DISPATCH=scoped*)
    # Extract everything after `images=`.
    images=$(printf '%s' "$dispatch_line" | sed 's/.*images=//' | tr -d '\r')
    emit_scoped "$images"
    ;;
  *)
    emit_full   # defensive fallback — never skip tests on parse error
    ;;
esac
