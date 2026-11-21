#!/usr/bin/env bash
# verify-promises-version-bump — if a PROMISES.yaml's promise set
# (the `- id:` lines) differs between base branch and HEAD/worktree,
# the file's `version:` field must also differ. (FG-083 Rule c.)
#
# Why: Adding or removing a promise is a contract-shape change.
# Prior-FG convention (FG-040, FG-046, etc.) bumps the file's
# `version:` by minor. FG-082 missed 3 bumps because nothing
# enforced the convention; FG-083 makes it a rule.
#
# Diff resolution:
#   1. If GIT_DIFF_BASE is set, use it (e.g. HEAD, origin/dev, SHA).
#   2. Else if GITHUB_BASE_REF is set (GitHub Actions PR context),
#      use origin/${GITHUB_BASE_REF}.
#   3. Else try origin/dev.
#   4. Else skip with a warning (exit 0) — this script needs git
#      context to be meaningful (shallow clone, detached HEAD).
#
# The comparison includes uncommitted worktree changes — `git diff
# ${BASE}` (no end-ref) compares BASE against the working tree, so a
# new promise staged but uncommitted still triggers the gate.

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- (1) resolve BASE ---
BASE="${GIT_DIFF_BASE:-}"
if [[ -z "$BASE" ]]; then
  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    BASE="origin/${GITHUB_BASE_REF}"
  else
    BASE="origin/dev"
  fi
fi

if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  echo "verify-promises-version-bump: ⚠ cannot resolve base '$BASE' (set GIT_DIFF_BASE or add origin/dev remote) — skipped."
  exit 0
fi

# --- (2) collect changed PROMISES.yaml files ---
# `git diff --name-only $BASE` compares BASE..worktree (covers both
# committed and uncommitted changes).
mapfile -t changed < <(git diff --name-only "$BASE" -- 'images/*/PROMISES.yaml' 'images/*/*/PROMISES.yaml' 2>/dev/null || true)

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "verify-promises-version-bump: ok (no PROMISES.yaml changed vs $BASE)."
  exit 0
fi

# --- (3) per changed file, compare promise count + version ---
fail=0
for f in "${changed[@]}"; do
  [[ -f "$f" ]] || continue  # file may have been deleted in HEAD; skip

  # Promise count in BASE and in HEAD/worktree.
  base_ids=$(git show "${BASE}:${f}" 2>/dev/null | grep -cE '^  - id: ' || true)
  head_ids=$(grep -cE '^  - id: ' "$f" || true)

  if [[ "$base_ids" == "$head_ids" ]]; then
    continue  # no promise-count change → no bump required
  fi

  # Promise count changed. Verify version: differs.
  base_version=$(git show "${BASE}:${f}" 2>/dev/null | awk -F'"' '/^version:/ {print $2; exit}')
  head_version=$(awk -F'"' '/^version:/ {print $2; exit}' "$f")

  if [[ "$base_version" == "$head_version" ]]; then
    echo "FAIL: ${f}: promise count changed (${base_ids} → ${head_ids}) but version: unchanged (\"${head_version}\")" >&2
    echo "  Bump version: (minor for additive, major if removing). Prior-FG convention." >&2
    fail=1
  fi
done

if [[ "$fail" -eq 0 ]]; then
  echo "verify-promises-version-bump: ok (${#changed[@]} PROMISES.yaml checked vs $BASE)."
fi

exit "$fail"
