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
# FG-059: split the former blanket `^scripts/` into (a) core scripts that
# actually affect every image's build and (b) image-helper scripts that
# fall through to the normal affected-images path. The implicit assumption
# for "scoped non-core script change" is that any image needing the helper
# script's new behavior exercises it in its smoke suite, which runs as
# part of the normal flow when that image is in AFFECTED (via its dir).
_CORE_SCRIPTS=(
  scripts/build-image.sh
  scripts/affected_images.py
  scripts/smart-check.sh
  scripts/_image_yaml.sh
  scripts/discover-images.sh
  scripts/stamp-image.sh
  scripts/scan-regression.py
  scripts/verify-no-upstream-drift.sh
  scripts/verify-traceability.sh
  scripts/verify-contracts.py
  scripts/contracts-semver-check.py
  scripts/install-tool-from-docker.sh
  scripts/image_from_graph.py
  scripts/scan-baseline-update.py
  scripts/smoke-server.sh
)

# Always-full triggers: Makefile, pre-commit, workflow, scratch-base dir.
FULL_RE='^(Makefile$|\.pre-commit-config\.yaml$|\.github/workflows/|images/scratch-base-trixie/)'
BAILOUT_HIT=$(echo "${CHANGED}" | grep -E "${FULL_RE}" | head -1 || true)
if [[ -n "${BAILOUT_HIT}" ]]; then
  say "full-run bailout — ${BAILOUT_HIT} touched"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=full reason=tooling-or-baseline path=${BAILOUT_HIT}"; exit 0; fi
  exec make check-strict
fi

# Core-script triggers: a core script affects every image — full-run.
CORE_HIT=""
for s in "${_CORE_SCRIPTS[@]}"; do
  if echo "${CHANGED}" | grep -qxF "${s}"; then
    CORE_HIT="${s}"
    break
  fi
done
if [[ -n "${CORE_HIT}" ]]; then
  say "full-run bailout — core script ${CORE_HIT} touched"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=full reason=tooling-core path=${CORE_HIT}"; exit 0; fi
  exec make check-strict
fi

# Compute classified affected image set.
# FG-060: --classify tags each entry with direct: or fanout: so we can
# serialize the direct phase (fan-out children FROM them) then
# parallelize the fan-out phase via xargs -P.
mapfile -t CLASSIFIED < <(python3 scripts/affected_images.py --classify "${BASE}")
DIRECT=()
FANOUT=()
for _line in "${CLASSIFIED[@]}"; do
  case "${_line}" in
    direct:*) DIRECT+=("${_line#direct:}") ;;
    fanout:*) FANOUT+=("${_line#fanout:}") ;;
  esac
done
AFFECTED=("${DIRECT[@]}" "${FANOUT[@]}")

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

if [[ ${#AFFECTED[@]} -gt 7 ]]; then
  say "full-run bailout — ${#AFFECTED[@]} images affected (cap is 7)"
  if [[ "${DRY_RUN}" == "1" ]]; then echo "DISPATCH=full reason=image-count count=${#AFFECTED[@]}"; exit 0; fi
  exec make check-strict
fi

# ── (3) Scoped run ────────────────────────────────────────────────────────────
# FG-060: parallelism for the fan-out phase. Default cap = max(1, nproc/4)
# so a 16-core workstation uses 4 parallel builds; a 4-core laptop uses 1
# (= serial, same as pre-FG-060). Override via FORGE_PARALLEL=N env.
_NPROC=$(nproc 2>/dev/null || echo 4)
_DEFAULT_CAP=$(( _NPROC / 4 ))
[[ "${_DEFAULT_CAP}" -lt 1 ]] && _DEFAULT_CAP=1
FANOUT_CAP="${FORGE_PARALLEL:-${_DEFAULT_CAP}}"

say "scoped run — ${#AFFECTED[@]} image(s) total (direct=${#DIRECT[@]}, fanout=${#FANOUT[@]}, parallelism=${FANOUT_CAP})"
say "  direct: ${DIRECT[*]:-<none>}"
say "  fanout: ${FANOUT[*]:-<none>}"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "DISPATCH=scoped count=${#AFFECTED[@]} direct_count=${#DIRECT[@]} fanout_count=${#FANOUT[@]} FANOUT_PARALLEL=${FANOUT_CAP} images=${AFFECTED[*]}"
  exit 0
fi

# 1) test-fast (full-repo lint + all verify-*; never scoped — see FG-017 C).
make test-fast

# 2) DIRECT phase — serial. Fan-out children FROM these locally, so their
#    `forge-local/<repo>:<tag>` must exist before the fan-out phase starts.
for img in "${DIRECT[@]}"; do
  bash scripts/smart-check-image.sh "${img}"
done

# 3) FANOUT phase — parallel. Each worker is independent; log lines
#    prefixed with [<image>] so output stays attributable.
if [[ ${#FANOUT[@]} -gt 0 ]]; then
  say "starting fan-out phase: ${#FANOUT[@]} image(s), parallelism=${FANOUT_CAP}"
  printf '%s\n' "${FANOUT[@]}" \
    | xargs -r -n1 -P "${FANOUT_CAP}" bash scripts/smart-check-image.sh
fi

# 4) verify-contracts always — cheap, catches graph regressions even in a
#    scoped run.
python3 scripts/verify-contracts.py

echo
say "smart-check passed (${#AFFECTED[@]} image(s) scoped)"
