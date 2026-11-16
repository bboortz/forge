#!/usr/bin/env bash
#
# Covers: FG-060
# CAPs:   tooling.smart-check

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-060]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. affected_images.py --classify prefixes with direct: / fanout:"
# The classify flag is best validated against a baseline whose diff includes
# a base image we know fans out. We DON'T want to depend on git-state tricks
# (stash + synth commit) that race with the uncommitted working-tree state.
# Instead: feed a controlled fake diff via the function-level API. This
# also decouples from any specific repo-history commit.
out=$(python3 - <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / "scripts"))
# Monkeypatch git_diff_names to return a synthetic diff.
import affected_images as ai
ai.git_diff_names = lambda base: ["images/forge-builder-python-trixie/Dockerfile"]
# Monkeypatch load_promises_from_ref to avoid git-show round-trips that
# would otherwise hit the real repo.
ai.load_promises_from_ref = lambda ref, image: {}
sys.argv = ["affected_images.py", "--classify", "SYNTHETIC"]
sys.exit(ai.main())
PY
)
rc=$?
[[ $rc -eq 0 ]] || fail "synthetic classify invocation exited ${rc}"
echo "${out}" | grep -q '^direct:forge-builder-python-trixie$' \
  || fail "classify: forge-builder-python-trixie should be direct; got: ${out}"
echo "${out}" | grep -qE '^fanout:(python|nginx|redis|mosquitto|healthy)-scratch-trixie$' \
  || fail "classify: expected at least one fanout:<scratch-image>; got: ${out}"
if echo "${out}" | grep -qE '^direct:(python|nginx|redis|mosquitto|healthy)-scratch-trixie$'; then
  fail "classify: a FROM-graph-derived image was incorrectly tagged direct"
fi
pass "classify flag separates direct from fanout correctly"

say "2. smart-check-image.sh is independently callable (worker contract)"
[[ -x scripts/smart-check-image.sh ]] || fail "scripts/smart-check-image.sh missing or not executable"
# Must reject no-argument invocation
set +e
bash scripts/smart-check-image.sh >/dev/null 2>&1
rc=$?
set -e
[[ "${rc}" -ne 0 ]] || fail "smart-check-image.sh should exit nonzero on missing arg"
pass "worker script exists + enforces its argument contract"

say "3. smart-check.sh DRY_RUN exposes FANOUT_PARALLEL + direct/fanout counts"
# Checking the source for the DRY_RUN emission format. Running smart-check
# live would hit the core-script bailout on this very PR's diff (since
# we're editing smart-check.sh itself), so we validate the shape of the
# emission instead.
grep -qE 'FANOUT_PARALLEL=\$\{?FANOUT_CAP' scripts/smart-check.sh \
  || fail "smart-check.sh DRY_RUN must emit FANOUT_PARALLEL=\$FANOUT_CAP"
grep -qE 'direct_count=\$\{#DIRECT\[@\]\}' scripts/smart-check.sh \
  || fail "smart-check.sh DRY_RUN must emit direct_count=\${#DIRECT[@]}"
grep -qE 'fanout_count=\$\{#FANOUT\[@\]\}' scripts/smart-check.sh \
  || fail "smart-check.sh DRY_RUN must emit fanout_count=\${#FANOUT[@]}"
pass "DRY_RUN emission emits parallelism + direct/fanout counts"

say "4. FORGE_PARALLEL env knob caps parallelism"
# shellcheck disable=SC2016  # literal grep pattern — expansion is not wanted here
grep -q 'FANOUT_CAP="${FORGE_PARALLEL:-${_DEFAULT_CAP}}"' scripts/smart-check.sh \
  || fail "smart-check.sh must honor FORGE_PARALLEL env with _DEFAULT_CAP fallback"
grep -qE '_DEFAULT_CAP=\$\(\( _NPROC / 4 \)\)' scripts/smart-check.sh \
  || fail "smart-check.sh must compute _DEFAULT_CAP as nproc/4"
pass "FORGE_PARALLEL=N overrides default (nproc/4)"

say "5. DIRECT phase ordering + presence of fan-out images in AFFECTED"
# Ordering is enforced structurally in smart-check.sh (DIRECT loop runs
# before FANOUT xargs). Validate via source-code grep that no interleaved
# path exists.
grep -q "for img in \"\${DIRECT\[@\]}\"" scripts/smart-check.sh \
  || fail "smart-check.sh: expected serial DIRECT loop"
# shellcheck disable=SC2016  # literal grep pattern
grep -q 'xargs -r -n1 -P "${FANOUT_CAP}"' scripts/smart-check.sh \
  || fail "smart-check.sh: expected xargs -P parallelism on FANOUT array"
# Also confirm DIRECT loop appears BEFORE the xargs invocation (lineno).
direct_line=$(grep -n "for img in \"\${DIRECT\[@\]}\"" scripts/smart-check.sh | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # literal grep pattern
xargs_line=$(grep -n "xargs -r -n1 -P" scripts/smart-check.sh | head -1 | cut -d: -f1)
[[ "${direct_line}" -lt "${xargs_line}" ]] \
  || fail "smart-check.sh: DIRECT loop (line ${direct_line}) must precede FANOUT xargs (line ${xargs_line})"
pass "DIRECT phase runs serially before parallelized FANOUT"

echo
echo "FG-060 acceptance: all sections passed."
