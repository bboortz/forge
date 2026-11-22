#!/usr/bin/env bash
#
# Covers: FG-086
# CAPs:   docs.three-folder-structure, docs.no-stale-refs-gate
#
# FG-086: docs/ is organised into exactly three subdirectories (specs, plan,
# stories). The 6 pre-FG-086 top-level docs + the mis-placed tier-layering
# spec move into docs/specs/. Every active (non-historical) reference in the
# repo resolves to the new path; historical FG-*-plan.md / FG-*.md are left
# alone by design.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-086]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — layout: three subdirs; correct contents per subdir
# -----------------------------------------------------------------------------
say "1. docs/ layout = {specs, plan, stories}/ only; correct allowed-file-sets"

# (1a) top-level entries = exactly these three dirs, no stray files.
top_entries=$(find docs/ -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | paste -sd ',' -)
[[ "${top_entries}" == "plan,specs,stories" ]] \
  || fail "docs/ top-level must be exactly 'plan,specs,stories' — got '${top_entries}'"
pass "docs/ top-level = specs/, plan/, stories/ (no stray files)"

# (1b) docs/specs/ contains the 7 canonical specs (5 .md + dep-graph pair) +
#      docs-structure.md (this FG's spec).
for f in \
    docs/specs/CAPABILITIES.md \
    docs/specs/LAYERING.md \
    docs/specs/baseline-contract.md \
    docs/specs/differentiators.md \
    docs/specs/tier-layering-model.md \
    docs/specs/image-dependency-graph.md \
    docs/specs/image-dependency-graph.svg \
    docs/specs/docs-structure.md; do
  [[ -f "${f}" ]] || fail "missing expected spec: ${f}"
done
pass "docs/specs/ has all 8 expected files (5 canonical specs + 2 generated artifacts + docs-structure)"

# (1c) docs/plan/ contains only FG-NNN-*-plan.md | IDEAS.md | _template.md.
bad=$(find docs/plan/ -mindepth 1 -maxdepth 1 -type f \
      \! -name 'FG-[0-9][0-9][0-9]-*-plan.md' \
      \! -name 'IDEAS.md' \
      \! -name '_template.md' \
      -printf '%f\n' | LC_ALL=C sort)
if [[ -n "${bad}" ]]; then
  fail "docs/plan/ has unexpected entries: ${bad}"
fi
pass "docs/plan/ contains only FG-NNN-*-plan.md, IDEAS.md, _template.md"

# (1d) docs/stories/ contains only FG-NNN-*.md | INDEX.md | _template.md | _9-questions.md.
bad=$(find docs/stories/ -mindepth 1 -maxdepth 1 -type f \
      \! -name 'FG-[0-9][0-9][0-9]-*.md' \
      \! -name 'INDEX.md' \
      \! -name '_template.md' \
      \! -name '_9-questions.md' \
      -printf '%f\n' | LC_ALL=C sort)
if [[ -n "${bad}" ]]; then
  fail "docs/stories/ has unexpected entries: ${bad}"
fi
pass "docs/stories/ contains only FG-NNN-*.md, INDEX.md, _template.md, _9-questions.md"

# -----------------------------------------------------------------------------
# Section 2 — no active file references pre-FG-086 doc paths
# -----------------------------------------------------------------------------
say "2. no active (non-historical) file references pre-FG-086 doc paths"

# Pre-FG-086 paths that MUST NOT appear in any active file. Historical
# docs/plan/FG-*-plan.md + docs/stories/FG-*.md are explicitly excluded.
# docs/specs/tier-layering-model.md intentionally contains its own self-ref
# via the frontmatter line — excluded below via :docs/specs/ prefix match.
stale_paths=(
  'docs/CAPABILITIES.md'
  'docs/LAYERING.md'
  'docs/baseline-contract.md'
  'docs/differentiators.md'
  'docs/image-dependency-graph.md'
  'docs/image-dependency-graph.svg'
  'docs/plan/tier-layering-model.md'
)

# Active surfaces to sweep. Historical files (docs/plan/FG-*-plan.md,
# docs/stories/FG-*.md) are intentionally omitted.
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
  'docs/specs/*.md'
  'docs/stories/_template.md'
  'docs/stories/_9-questions.md'
  'docs/stories/INDEX.md'
  'docs/plan/_template.md'
  'docs/plan/IDEAS.md'
  '.github/workflows/*.yml'
)

# Build the file list with shell globs (not git ls-files so this works for
# uncommitted paths too).
active_files=()
shopt -s nullglob
for g in "${active_globs[@]}"; do
  # shellcheck disable=SC2206
  matches=( ${g} )
  active_files+=( "${matches[@]}" )
done
shopt -u nullglob

total_stale=0
for p in "${stale_paths[@]}"; do
  # Use fgrep + -F for literal path match; exclude self (this test file) + the
  # tier-layering-model.md self-ref line (its frontmatter `spans:` block).
  # Legitimate self-refs excluded:
  #   - this test file (the test asserts itself)
  #   - docs/specs/docs-structure.md (design doc, describes the move)
  #   - docs/specs/tier-layering-model.md (may self-reference its old location in history)
  #   - scripts/verify-docs-structure.sh (contains the literal allowlist)
  #   - docs/specs/CAPABILITIES.md's docs.no-stale-refs-gate CAP enumerates the paths
  hits=$(grep -nF -- "${p}" "${active_files[@]}" 2>/dev/null \
         | grep -v "tests/acceptance/test_FG_086_docs-structure.sh" \
         | grep -v "docs/specs/docs-structure.md:" \
         | grep -v "^docs/specs/tier-layering-model.md:" \
         | grep -v "^scripts/verify-docs-structure.sh:" \
         | grep -v "^docs/specs/CAPABILITIES.md:" \
         || true)
  if [[ -n "${hits}" ]]; then
    printf '  stale ref to %s:\n' "${p}" >&2
    printf '%s\n' "${hits}" | sed 's/^/    /' >&2
    total_stale=$(( total_stale + 1 ))
  fi
done
[[ "${total_stale}" -eq 0 ]] || fail "${total_stale} pre-FG-086 doc path(s) still referenced in active files"
pass "zero stale refs to pre-FG-086 paths in Makefile / scripts / tests / memory / CLAUDE / README / pre-commit / PROMISES / images / .github workflows / templates"

# -----------------------------------------------------------------------------
# Section 3 — verify-docs-structure.sh exists, is wired into test-fast, green
# -----------------------------------------------------------------------------
say "3. scripts/verify-docs-structure.sh exists + wired + passes"

[[ -x scripts/verify-docs-structure.sh ]] \
  || fail "scripts/verify-docs-structure.sh must exist and be executable"
pass "scripts/verify-docs-structure.sh exists + executable"

grep -q 'verify-docs-structure' Makefile \
  || fail "Makefile must wire verify-docs-structure into test-fast"
pass "Makefile references verify-docs-structure"

bash scripts/verify-docs-structure.sh \
  || fail "scripts/verify-docs-structure.sh fails on current tree"
pass "verify-docs-structure.sh exits 0 on current tree"

# -----------------------------------------------------------------------------
# Section 4 — structural gate blocks drift (negative test)
# -----------------------------------------------------------------------------
say "4. verify-docs-structure fails when a stray top-level doc appears"

tmp="docs/_stray_fg086_test.md"
: > "${tmp}"
trap 'rm -f "${tmp}"' EXIT
set +e
out=$(bash scripts/verify-docs-structure.sh 2>&1)
rc=$?
set -e
[[ "${rc}" -ne 0 ]] \
  || fail "verify-docs-structure must fail when docs/ has a stray top-level file"
grep -qi 'stray\|unexpected\|top-level\|docs/_stray_fg086_test\.md' <<<"${out}" \
  || fail "verify-docs-structure output must name the offending file — got: ${out}"
pass "verify-docs-structure rejects stray top-level file"

rm -f "${tmp}"
trap - EXIT

# -----------------------------------------------------------------------------
# Section 5 — Makefile dep-graph + mermaid-to-svg wired to docs/specs/
# -----------------------------------------------------------------------------
say "5. dep-graph tooling points at docs/specs/"

grep -q 'docs/specs/image-dependency-graph.md' Makefile \
  || fail "Makefile must reference docs/specs/image-dependency-graph.md"
grep -q 'docs/specs/image-dependency-graph.svg' Makefile \
  || fail "Makefile must reference docs/specs/image-dependency-graph.svg"
grep -q 'docs/specs/image-dependency-graph.md' scripts/mermaid-to-svg.sh \
  || fail "scripts/mermaid-to-svg.sh must reference docs/specs/image-dependency-graph.md"
grep -q 'docs/specs/image-dependency-graph.svg' scripts/mermaid-to-svg.sh \
  || fail "scripts/mermaid-to-svg.sh must reference docs/specs/image-dependency-graph.svg"
pass "Makefile + mermaid-to-svg.sh updated"

# -----------------------------------------------------------------------------
# Section 6 — CAPs registered
# -----------------------------------------------------------------------------
say "6. docs/specs/CAPABILITIES.md registers the two new CAPs"
grep -q '^### docs\.three-folder-structure' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### docs.three-folder-structure"
grep -q '^### docs\.no-stale-refs-gate' docs/specs/CAPABILITIES.md \
  || fail "docs/specs/CAPABILITIES.md missing ### docs.no-stale-refs-gate"
pass "both FG-086 CAPs registered"

# -----------------------------------------------------------------------------
# Section 7 — INDEX reflects FG-086
# -----------------------------------------------------------------------------
say "7. docs/stories/INDEX.md lists FG-086"
grep -q 'FG-086' docs/stories/INDEX.md \
  || fail "docs/stories/INDEX.md missing FG-086 row"
pass "INDEX includes FG-086"

echo
echo "FG-086 acceptance: all sections passed."
