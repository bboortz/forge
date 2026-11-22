#!/usr/bin/env bash
# Enforce bidirectional story ↔ plan ↔ test ↔ CAP links:
#   1. Every CAP in docs/specs/CAPABILITIES.md has a `Covered by:` pointer.
#   2. Every tests/acceptance/test_FG_*.sh has a `# CAPs:` header line
#      and the CAPs it names all exist in CAPABILITIES.md.
#   3. Every story with status ready / in-progress / shipped lists at
#      least one CAP id (NEW or EXT) in question 9.
set -euo pipefail

caps_file="docs/specs/CAPABILITIES.md"
fail=0

if [[ ! -f "$caps_file" ]]; then
  echo "FAIL: $caps_file is missing." >&2
  exit 1
fi

mapfile -t known_caps < <(grep -E '^### [a-z]+\.[a-z0-9-]+$' "$caps_file" | sed 's/^### //')

# 1. Every known CAP must have a 'Covered by:' pointer in its section.
for cap in "${known_caps[@]}"; do
  if ! awk -v cap="### $cap" '
      $0 == cap { inside = 1; next }
      inside && /^### / { exit 1 }
      inside && /Covered by/ { found = 1; exit 0 }
      END { exit !found }
    ' "$caps_file"; then
    echo "FAIL: CAP $cap has no 'Covered by:' pointer in $caps_file" >&2
    fail=1
  fi
done

# 2. Every acceptance test must have a '# CAPs:' header; every CAP it names must be known.
shopt -s nullglob
for test in tests/acceptance/test_FG_*.sh; do
  if ! grep -q -E '^# *CAPs:' "$test"; then
    echo "FAIL: $test is missing a '# CAPs:' header line" >&2
    fail=1
    continue
  fi
  caps_block=$(awk '/^# *CAPs:/{flag=1} flag && /^#?[[:space:]]*$/{exit} flag' "$test" | sed 's/^#[[:space:]]*CAPs:[[:space:]]*//; s/^#//')
  for cap_in_test in $(echo "$caps_block" | tr ',' '\n' | tr -s '[:space:]' '\n' | grep -E '^[a-z]+\.[a-z0-9-]+$' || true); do
    found=0
    for k in "${known_caps[@]}"; do
      if [[ "$k" == "$cap_in_test" ]]; then found=1; break; fi
    done
    if [[ $found -eq 0 ]]; then
      echo "FAIL: $test references unknown CAP: $cap_in_test" >&2
      fail=1
    fi
  done
done

# 3. Every ready+ story must list ≥ 1 CAP id in question 9.
for story in docs/stories/FG-*.md; do
  status=$(awk '/^status:/{print $2; exit}' "$story")
  case "$status" in
    ready|in-progress|shipped) ;;
    *) continue ;;
  esac
  # shellcheck disable=SC2016  # single-quoted grep pattern is intentional
  if ! grep -E -q '^[[:space:]]*- (NEW|EXT) `[a-z]+\.[a-z0-9-]+`' "$story"; then
    echo "FAIL: $story (status $status) lacks CAP ids (NEW/EXT) in question 9" >&2
    fail=1
  fi
done

# 4. Every `image.*` CAP must have ≥1 PROMISES entry mentioning it via
#    caps:. Non-`image.*` CAPs (arch./build./ci./tooling./...) are
#    architecture / pipeline / meta invariants and don't belong in any
#    image's per-promise caps list — they're covered via acceptance tests.
#    This closes the CAP ⇆ PROMISES bidirectional gap left by Rules 1-3
#    (which only enforce CAP ⇆ test and CAP ⇆ story). FG-083.
if command -v python3 >/dev/null 2>&1; then
  if ! _traceability_rule_4=$(python3 - <<'PY' 2>&1
import sys, re
from pathlib import Path
try:
    import yaml
except ImportError:
    # Soft-skip if PyYAML missing; the python-based verify-contracts gate
    # in test-fast has the same dep + prints its own install hint.
    print("warn: PyYAML missing — Rule 4 skipped", file=sys.stderr)
    sys.exit(0)

root = Path(".")
known = set()
for line in (root / "docs/specs/CAPABILITIES.md").read_text().splitlines():
    m = re.match(r"^### ([a-z]+\.[a-z0-9-]+)$", line)
    if m:
        known.add(m.group(1))

promised = set()
for p in list(root.glob("images/*/PROMISES.yaml")) + list(root.glob("images/*/*/PROMISES.yaml")):
    try:
        d = yaml.safe_load(p.read_text())
    except Exception as e:
        print(f"FAIL: cannot parse {p}: {e}", file=sys.stderr)
        sys.exit(1)
    for prom in (d or {}).get("promises", []) or []:
        for c in prom.get("caps", []) or []:
            promised.add(c)

# Only image.* CAPs are image-level contracts; others are meta.
image_caps = {c for c in known if c.startswith("image.")}
uncovered = sorted(image_caps - promised)
if uncovered:
    print(f"FAIL: {len(uncovered)} image.* CAP(s) have zero PROMISES.caps coverage:", file=sys.stderr)
    for c in uncovered:
        print(f"  {c}", file=sys.stderr)
    print("\nEvery image.* CAP must be referenced by at least one promise's caps: entry.", file=sys.stderr)
    sys.exit(1)
PY
  ); then
    echo "$_traceability_rule_4" >&2
    fail=1
  fi
fi

if [[ $fail -eq 0 ]]; then
  echo "verify-traceability: ok (${#known_caps[@]} CAP(s) tracked)."
fi
exit $fail
