#!/usr/bin/env bash
# FG-086 — Enforce the three-folder docs/ convention.
#
#   docs/
#     specs/     canonical rules + contracts (open file set)
#     plan/      FG-NNN-*-plan.md + IDEAS.md + _template.md
#     stories/   FG-NNN-*.md + INDEX.md + _template.md + _9-questions.md
#
# Rules:
#   1. docs/ top-level contains only the three sibling directories (no files).
#   2. docs/plan/ matches the allowed-file-set.
#   3. docs/stories/ matches the allowed-file-set.
#   4. No active (non-historical) file references pre-FG-086 doc paths.
#
# Historical (docs/plan/FG-*-plan.md, docs/stories/FG-*.md) are frozen-in-time
# records and may reference pre-FG-086 paths. Everything else must not.
#
# Wired into `make test-fast`. Full spec: docs/specs/docs-structure.md.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
err() { printf '  ✗ %s\n' "$*" >&2; fail=1; }

# -----------------------------------------------------------------------------
# Rule 1 — docs/ top-level: exactly {specs, plan, stories}/, no stray files
# -----------------------------------------------------------------------------
stray_files=$(find docs/ -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
if [[ -n "${stray_files}" ]]; then
  err "docs/ has stray top-level file(s): ${stray_files}. Move them into docs/specs/, docs/plan/, or docs/stories/."
fi

top_dirs=$(find docs/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | paste -sd ',' -)
if [[ "${top_dirs}" != "plan,specs,stories" ]]; then
  err "docs/ top-level dirs must be exactly 'plan,specs,stories' — got '${top_dirs}'"
fi

# -----------------------------------------------------------------------------
# Rule 2 — docs/plan/ allowed-file-set
# -----------------------------------------------------------------------------
bad_plan=$(find docs/plan/ -mindepth 1 -maxdepth 1 -type f \
           \! -name 'FG-[0-9][0-9][0-9]-*-plan.md' \
           \! -name 'IDEAS.md' \
           \! -name '_template.md' \
           -printf '%f\n' | LC_ALL=C sort)
if [[ -n "${bad_plan}" ]]; then
  err "docs/plan/ has unexpected entries: ${bad_plan}. Allowed: FG-NNN-*-plan.md, IDEAS.md, _template.md."
fi
bad_plan_dirs=$(find docs/plan/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [[ -n "${bad_plan_dirs}" ]]; then
  err "docs/plan/ must not contain subdirectories — got: ${bad_plan_dirs}"
fi

# -----------------------------------------------------------------------------
# Rule 3 — docs/stories/ allowed-file-set
# -----------------------------------------------------------------------------
bad_stories=$(find docs/stories/ -mindepth 1 -maxdepth 1 -type f \
              \! -name 'FG-[0-9][0-9][0-9]-*.md' \
              \! -name 'INDEX.md' \
              \! -name '_template.md' \
              \! -name '_9-questions.md' \
              -printf '%f\n' | LC_ALL=C sort)
if [[ -n "${bad_stories}" ]]; then
  err "docs/stories/ has unexpected entries: ${bad_stories}. Allowed: FG-NNN-*.md, INDEX.md, _template.md, _9-questions.md."
fi
bad_story_dirs=$(find docs/stories/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [[ -n "${bad_story_dirs}" ]]; then
  err "docs/stories/ must not contain subdirectories — got: ${bad_story_dirs}"
fi

# -----------------------------------------------------------------------------
# Rule 4 — no active file references pre-FG-086 doc paths
# -----------------------------------------------------------------------------
# The seven pre-FG-086 doc paths that were moved by FG-086. Any active file
# still naming one of these is a stale reference that must be fixed in the
# same PR, not grandfathered (see docs/specs/docs-structure.md § Reference
# migration policy).
stale_paths=(
  'docs/CAPABILITIES.md'
  'docs/LAYERING.md'
  'docs/baseline-contract.md'
  'docs/differentiators.md'
  'docs/image-dependency-graph.md'
  'docs/image-dependency-graph.svg'
  'docs/plan/tier-layering-model.md'
)

# Active surfaces (anything that's NOT a frozen historical FG record).
active_globs=(
  Makefile
  README.md
  CLAUDE.md
  .pre-commit-config.yaml
  'memory/*.md'
  'scripts/*.sh'
  'scripts/*.py'
  'tests/acceptance/*.sh'
  'tests/unit/*'
  'images/*/PROMISES.yaml'
  'images/*/EXPECTATIONS.yaml'
  'images/*/image.yaml'
  'images/*/Dockerfile'
  'images/*/*/PROMISES.yaml'
  'images/*/*/EXPECTATIONS.yaml'
  'images/*/*/image.yaml'
  'images/*/*/Dockerfile'
  'docs/specs/*.md'
  'docs/stories/_template.md'
  'docs/stories/_9-questions.md'
  'docs/stories/INDEX.md'
  'docs/plan/_template.md'
  'docs/plan/IDEAS.md'
  '.github/workflows/*.yml'
)

active_files=()
shopt -s nullglob
for g in "${active_globs[@]}"; do
  # shellcheck disable=SC2206  # intentional word-splitting on glob expansion
  matches=( ${g} )
  active_files+=( "${matches[@]}" )
done
shopt -u nullglob

if [[ "${#active_files[@]}" -gt 0 ]]; then
  for p in "${stale_paths[@]}"; do
    # Literal match, exclude self-refs:
    #   - docs/specs/docs-structure.md intentionally lists the old paths in prose
    #   - docs/specs/tier-layering-model.md may self-reference its own old path in historical sections
    #   - docs/specs/CAPABILITIES.md's docs.no-stale-refs-gate CAP enumerates the paths
    #   - scripts/verify-docs-structure.sh (this file) is the source of the allowlist above
    #   - tests/acceptance/test_FG_086_docs-structure.sh is the FG's acceptance test
    hits=$(grep -nF -- "${p}" "${active_files[@]}" 2>/dev/null \
           | grep -v '^docs/specs/docs-structure.md:' \
           | grep -v '^docs/specs/tier-layering-model.md:' \
           | grep -v '^docs/specs/CAPABILITIES.md:' \
           | grep -v '^scripts/verify-docs-structure.sh:' \
           | grep -v '^tests/acceptance/test_FG_086_docs-structure.sh:' \
           || true)
    if [[ -n "${hits}" ]]; then
      err "stale ref to ${p}:"
      printf '%s\n' "${hits}" | sed 's/^/      /' >&2
    fi
  done
fi

if [[ "${fail}" -eq 0 ]]; then
  echo "verify-docs-structure: ok"
fi
exit "${fail}"
