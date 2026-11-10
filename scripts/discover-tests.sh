#!/usr/bin/env bash
# FG-024: emit a GHA matrix spec of all acceptance tests.
# Output on stdout: {"include":[{"test":"<path>","fg_id":"FG-NNN"},...]}
#
# Used by .github/workflows/ci.yml to fan out one GHA job per test.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Discover all test_FG_<NNN>_*.sh under tests/acceptance/ in sorted order.
# Reject non-executable or oddly-named files (keeps the matrix list clean).
mapfile -t TESTS < <(find tests/acceptance -type f -name 'test_FG_*.sh' | sort)

if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "discover-tests.sh: no tests found under tests/acceptance/" >&2
  exit 1
fi

# Build the matrix include array one entry per test.
first=1
printf '{"include":['
for t in "${TESTS[@]}"; do
  base=$(basename "${t}")
  # FG-046 introduced split tests with letter-suffixes (test_FG_046a_… etc.)
  # so each sub-test gets its own matrix cell under the 6-min timeout cap.
  # fg_id for split tests is "FG-NNN<letter>" (e.g. FG-046a); otherwise FG-NNN.
  if [[ "${base}" =~ ^test_FG_([0-9]{3})([a-z]?)_ ]]; then
    fg_id="FG-${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  else
    echo "discover-tests.sh: cannot parse FG id from ${t}" >&2
    exit 1
  fi
  if [[ "${first}" == "1" ]]; then
    first=0
  else
    printf ','
  fi
  printf '{"test":"%s","fg_id":"%s"}' "${t}" "${fg_id}"
done
printf ']}'
echo
