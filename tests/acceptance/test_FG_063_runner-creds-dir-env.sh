#!/usr/bin/env bash
#
# Covers: FG-063
# CAPs:   image.github-runner-creds-dir, image.github-runner-noble-pre-baked
#
# shellcheck disable=SC2016  # many greps assert literal $VAR patterns in the entrypoint

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-063]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "1. entrypoint.sh declares RUNNER_CREDS_DIR with default = RUNNER_DIR"
EP=images/github-runner-noble/entrypoint.sh
grep -q 'RUNNER_CREDS_DIR:-$RUNNER_DIR' "${EP}" \
  || fail "entrypoint must set RUNNER_CREDS_DIR=\${RUNNER_CREDS_DIR:-\$RUNNER_DIR} (default /home/runner)"
pass "RUNNER_CREDS_DIR default = \$RUNNER_DIR"

say "2. entrypoint has two-phase persistence (restart pre-symlink + post-config mv)"
# Phase 1: gated on non-default RUNNER_CREDS_DIR + pre-existing RUNNER_CREDS_DIR/.runner.
# No dangling symlinks pre-created on first-start — regression guard for the
# fresh-volume crash where Runner.Listener configure follows a dangling
# .credentials symlink and throws FileNotFoundException.
grep -q 'RUNNER_CREDS_DIR}" != "${RUNNER_DIR}"' "${EP}" \
  || fail "entrypoint symlink block must be gated on RUNNER_CREDS_DIR != RUNNER_DIR"
grep -q '\-f "${RUNNER_CREDS_DIR}/.runner"' "${EP}" \
  || fail "Phase 1: entrypoint must gate the pre-symlink block on a pre-existing RUNNER_CREDS_DIR/.runner (restart case)"
grep -q 'if \[\[ -f "${RUNNER_CREDS_DIR}/${_f}" \]\]; then' "${EP}" \
  || fail "Phase 1: each credential symlink must be gated on file existence in RUNNER_CREDS_DIR (avoid dangling symlinks)"
grep -q 'ln -sf "${RUNNER_CREDS_DIR}/${_f}" "${RUNNER_DIR}/${_f}"' "${EP}" \
  || fail "Phase 1: entrypoint must ln -sf \${RUNNER_CREDS_DIR}/\${_f} \${RUNNER_DIR}/\${_f}"
# Phase 2: after config.sh, mv regular files into RUNNER_CREDS_DIR + symlink.
grep -q 'mv "${RUNNER_DIR}/${_f}" "${RUNNER_CREDS_DIR}/${_f}"' "${EP}" \
  || fail "Phase 2: entrypoint must mv \${RUNNER_DIR}/\${_f} \${RUNNER_CREDS_DIR}/\${_f} after config.sh (persist on first start)"
pass "two-phase: pre-symlink restart case + post-config.sh mv+symlink first-start case"

say "3. Dockerfile ENTRYPOINT unchanged (consumer contract preserved)"
grep -qE '^ENTRYPOINT \["/entrypoint.sh"\]' images/github-runner-noble/Dockerfile \
  || fail "Dockerfile ENTRYPOINT must remain [\"/entrypoint.sh\"]"
pass "ENTRYPOINT [\"/entrypoint.sh\"] preserved"

say "4. PROMISES.yaml bumped (≥ 0.3) + runtime.runner-creds-dir-env promise"
PP=images/github-runner-noble/PROMISES.yaml
grep -qE '^version: "0\.[3-9]' "${PP}" \
  || fail "PROMISES.yaml version must be ≥ 0.3 (two-phase persistence, promise description updated — FG-010 semver)"
grep -q 'id: runtime.runner-creds-dir-env' "${PP}" \
  || fail "PROMISES.yaml missing runtime.runner-creds-dir-env promise"
grep -q 'image.github-runner-creds-dir' "${PP}" \
  || fail "promise must link to image.github-runner-creds-dir CAP"
# Promise description must mention both phases + the dangling-symlink pitfall.
grep -q 'two-phase' "${PP}" \
  || fail "promise description must describe the two-phase scheme"
grep -q 'dangling' "${PP}" \
  || fail "promise description must call out the dangling-symlink crash avoidance"
pass "PROMISES.yaml ≥ 0.3 + two-phase + dangling-symlink note"

say "5. image.github-runner-creds-dir CAP registered in CAPABILITIES.md"
grep -qE '^### image\.github-runner-creds-dir$' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing ### image.github-runner-creds-dir section"
pass "CAP registered"

say "6. Full build + smokes (skip in fast-mode)"
if [[ "${FORGE_FAST:-0}" == "1" ]]; then
  pass "skipped per FORGE_FAST=1"
else
  FORGE_NO_SKIP=1 bash scripts/build-image.sh github-runner-noble >/dev/null 2>&1 \
    || fail "github-runner-noble build failed"
  IMAGE_NAME=github-runner-noble IMAGE_TAG=latest \
    bash images/github-runner-noble/tests/smoke_runner_creds_dir.sh >/dev/null \
    || fail "smoke_runner_creds_dir.sh failed"
  # Existing entrypoint-env-validation smoke must still pass (backward compat).
  IMAGE_NAME=github-runner-noble IMAGE_TAG=latest \
    bash images/github-runner-noble/tests/smoke_entrypoint_env_validation.sh >/dev/null \
    || fail "smoke_entrypoint_env_validation.sh regressed (default-case behavior changed)"
  pass "image built + FG-063 smoke + backward-compat smoke green"
fi

echo
echo "FG-063 acceptance: all sections passed."
