#!/usr/bin/env bash
# FG-017 — Smart pre-push gate.
#
# Three outcomes based on `git diff $BASE..HEAD`:
#   (1) test-fast only                       — docs-only diff
#   (2) full-run bailout → check-strict      — tooling/baseline/>4-images touched
#   (3) scoped run                           — else: test-fast + build + smoke +
#                                              acceptance for each affected image
#                                              + verify-contracts
#
# BASE ref ladder (mirrors homelab/scripts/test-updates.sh):
#   GITHUB_BASE_REF (set by GHA for PRs)  → origin/${GITHUB_BASE_REF}
#   GITHUB_EVENT_NAME=push (GHA for pushes) → HEAD^
#   else                                   → origin/dev
#
# Environment:
#   FORGE_FULL=1           force full-run (no scoping)
#   FORGE_SKIP_WIPE=1      don't `docker rmi` scoped images before rebuild
#   SMART_CHECK_DRY_RUN=1  print the planned dispatch + exit 0 without executing
#                          (used by tests/acceptance/test_FG_017_*.sh)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

say()  { printf '→ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

DRY_RUN="${SMART_CHECK_DRY_RUN:-0}"

# ── Determine BASE ref ────────────────────────────────────────────────────────
# _FORGE_BASE_OVERRIDE is a test-only hook used by the FG-017 acceptance test.
if [[ -n "${_FORGE_BASE_OVERRIDE:-}" ]]; then
  BASE="${_FORGE_BASE_OVERRIDE}"
elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  BASE="origin/${GITHUB_BASE_REF}"
elif [[ "${GITHUB_EVENT_NAME:-}" == "push" ]]; then
  BASE="HEAD^"
else
  BASE="origin/dev"
fi

# Resolve BASE; fall back to HEAD^ if origin/dev isn't fetched (new clones).
if ! git rev-parse --verify --quiet "${BASE}" >/dev/null; then
  warn "base ref ${BASE} not found — falling back to HEAD^"
  BASE="HEAD^"
fi

say "smart-check (BASE: ${BASE})"

# ── Collect changed paths ─────────────────────────────────────────────────────
CHANGED=$(git diff --name-only "${BASE}..HEAD" 2>/dev/null || echo "")

# ── Forced-full override ──────────────────────────────────────────────────────
if [[ "${FORGE_FULL:-0}" == "1" ]]; then
  say "FORGE_FULL=1 — delegating to make check-strict"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=full"; exit 0; fi
  exec make check-strict
fi

# ── (1) Docs/no-change short-circuit ──────────────────────────────────────────
if [[ -z "${CHANGED}" ]]; then
  say "no diff vs ${BASE} — running test-fast only"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=test-fast-only"; exit 0; fi
  exec make test-fast
fi

NON_DOC=$(echo "${CHANGED}" | grep -vE '\.md$|^docs/' || true)
if [[ -z "${NON_DOC}" ]]; then
  say "docs-only diff — running test-fast only"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=test-fast-only"; exit 0; fi
  exec make test-fast
fi

# ── (2) Full-run bailouts ─────────────────────────────────────────────────────
# Tooling, Makefile, pre-commit config, workflows, or baseline → full run.
FULL_RE='^(scripts/|Makefile$|\.pre-commit-config\.yaml$|\.github/workflows/|images/scratch-base-trixie/)'
BAILOUT_HIT=$(echo "${CHANGED}" | grep -E "${FULL_RE}" | head -1 || true)
if [[ -n "${BAILOUT_HIT}" ]]; then
  say "full-run bailout — ${BAILOUT_HIT} touched"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=full reason=tooling-or-baseline path=${BAILOUT_HIT}"; exit 0; fi
  exec make check-strict
fi

# Compute affected image set (direct + EXPECTATIONS fan-out).
mapfile -t AFFECTED < <(python3 scripts/affected_images.py "${BASE}")

if [[ ${#AFFECTED[@]} -eq 0 ]]; then
  # Non-doc diff touching nothing image-related (e.g. tests/acceptance/* or
  # memory/*). Run test-fast + acceptance for safety, skip builds.
  say "diff touches no images — running test-fast + test-acceptance (deduped)"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=non-image-diff"; exit 0; fi
  make test-fast
  _FORGE_IN_CHECK=1 make test-acceptance
  python3 scripts/verify-contracts.py
  exit 0
fi

if [[ ${#AFFECTED[@]} -gt 4 ]]; then
  say "full-run bailout — ${#AFFECTED[@]} images affected (cap is 4)"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=full reason=image-count count=${#AFFECTED[@]}"; exit 0; fi
  exec make check-strict
fi

# ── (3) Scoped run ────────────────────────────────────────────────────────────
say "scoped run — ${#AFFECTED[@]} image(s): ${AFFECTED[*]}"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "DISPATCH=scoped count=${#AFFECTED[@]} images=${AFFECTED[*]}"
  exit 0
fi

# 1) test-fast (full-repo lint + all verify-*; never scoped — see FG-017 C).
make test-fast

# 2) Per-image: optional wipe → build → smoke → acceptance (deduped).
# shellcheck source=scripts/_image_yaml.sh disable=SC1091
. scripts/_image_yaml.sh
for img in "${AFFECTED[@]}"; do
  iy="images/${img}/image.yaml"
  [[ -f "${iy}" ]] || { warn "missing ${iy}, skipping"; continue; }
  tag=$(image_yaml_get "${iy}" tag)
  repo=$(image_yaml_repo "${iy}")
  if [[ "${FORGE_SKIP_WIPE:-0}" != "1" ]]; then
    say "docker rmi forge-local/${repo}:${tag} (cold-cache rebuild for ${img})"
    docker rmi "forge-local/${repo}:${tag}" >/dev/null 2>&1 || true
  fi
  bash scripts/build-image.sh "${img}"
  bash scripts/test-images.sh "${img}"
  # Find the matching acceptance test (slug-based).
  shopt -s nullglob
  accept_tests=(tests/acceptance/test_FG_*_"${img#*-}"*.sh)
  # Also match "<image>-" prefix slug variants (e.g. python-scratch-trixie).
  if [[ ${#accept_tests[@]} -eq 0 ]]; then
    accept_tests=(tests/acceptance/test_FG_*"${img}"*.sh)
  fi
  shopt -u nullglob
  for t in "${accept_tests[@]}"; do
    say "acceptance: ${t}"
    _FORGE_IN_CHECK=1 bash "${t}"
  done
done

# 3) verify-contracts always — cheap, catches graph regressions even in a
#    scoped run.
python3 scripts/verify-contracts.py

echo
say "smart-check passed (${#AFFECTED[@]} image(s) scoped)"
