#!/usr/bin/env bash
# Enforce: every file under images/*/sid-pins/*.pref carries, in comments,
#   - a CVE reference      (CVE-YYYY-NNNNN)
#   - a removal condition  (word "remove" or "backport")
#   - a date-added         (YYYY-MM-DD)
#
# For FG-001 there are no pin files yet; this script passes vacuously.
set -euo pipefail
shopt -s nullglob

fail=0
pins=(images/*/sid-pins/*.pref)

for pin in "${pins[@]}"; do
  if ! grep -q -E 'CVE-[0-9]{4}-[0-9]+' "$pin"; then
    echo "FAIL: $pin: missing CVE reference (CVE-YYYY-NNNNN)" >&2
    fail=1
  fi
  if ! grep -q -i -E 'remove|backport' "$pin"; then
    echo "FAIL: $pin: missing removal condition (grep for 'remove' or 'backport')" >&2
    fail=1
  fi
  if ! grep -q -E '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$pin"; then
    echo "FAIL: $pin: missing date-added (YYYY-MM-DD)" >&2
    fail=1
  fi
done

if [[ ${#pins[@]} -eq 0 ]]; then
  echo "verify-sid-pins: no sid pins present (vacuous pass)."
else
  if [[ $fail -eq 0 ]]; then
    echo "verify-sid-pins: ${#pins[@]} pin(s) ok."
  fi
fi

exit $fail
