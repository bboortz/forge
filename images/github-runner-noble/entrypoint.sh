#!/bin/bash
# FG-051: GitHub Actions self-hosted runner entrypoint.
# FG-063: added RUNNER_CREDS_DIR env var for narrow credential-volume deploys.
#
# Behavior:
#   - Read GITHUB_ORG / GITHUB_RUNNER_PAT / RUNNER_NAME / RUNNER_LABELS env.
#   - Read RUNNER_CREDS_DIR env (default /home/runner). When non-default,
#     mkdir the target + symlink .runner, .credentials, .credentials_rsaparams
#     from /home/runner into RUNNER_CREDS_DIR so the runner binary tree under
#     /home/runner/bin/ stays image-layer owned (no more named-volume
#     binary-shadow bug — see FG-063 story).
#   - If /home/runner/.runner does NOT exist: request a registration token
#     from the GitHub Actions API + run config.sh --unattended --replace.
#   - If /home/runner/.runner DOES exist: skip registration, go straight
#     to run.sh.
#   - Exec run.sh as PID 1 so docker signal handling works correctly.
#
# Matches the behavior of homelab's current docker/github-runner/
# entrypoint.sh (which this forge image replaces at deploy time per
# FG-051 scope) + supersedes homelab's runner-entrypoint.sh wrapper
# (replaced by the RUNNER_CREDS_DIR env var per FG-063).

set -euo pipefail

RUNNER_DIR="/home/runner"
REG_FILE="${RUNNER_DIR}/.runner"
RUNNER_CREDS_DIR="${RUNNER_CREDS_DIR:-$RUNNER_DIR}"

# FG-063: when the operator points credential persistence at a path other
# than /home/runner (typically a narrow mounted volume at /runner-creds),
# redirect the three credential files via symlinks BEFORE config.sh runs.
# On first start the symlinks are dangling and config.sh writes through
# them; on later starts they resolve + the REG_FILE check below short-
# circuits registration. Binary tree (/home/runner/bin/ + externals/) is
# never shadowed, so forge image updates propagate every restart.
if [[ "${RUNNER_CREDS_DIR}" != "${RUNNER_DIR}" ]]; then
  mkdir -p "${RUNNER_CREDS_DIR}"
  for _f in .runner .credentials .credentials_rsaparams; do
    ln -sf "${RUNNER_CREDS_DIR}/${_f}" "${RUNNER_DIR}/${_f}"
  done
fi

if [[ -z "${GITHUB_ORG:-}" ]] && [[ ! -f "${REG_FILE}" ]]; then
  echo "ERROR: GITHUB_ORG env var is not set and no existing ${REG_FILE}." >&2
  echo "       Set GITHUB_ORG + GITHUB_RUNNER_PAT for first-start registration," >&2
  echo "       or mount a volume with an existing .runner + .credentials." >&2
  exit 1
fi

if [[ ! -f "${REG_FILE}" ]]; then
  if [[ -z "${GITHUB_RUNNER_PAT:-}" ]]; then
    echo "ERROR: GITHUB_RUNNER_PAT env var is not set. Needed for first-start" >&2
    echo "       registration token exchange with the GitHub Actions API." >&2
    exit 1
  fi

  echo "==> First start: registering runner with GitHub org ${GITHUB_ORG}..."
  TOKEN=$(curl -sSL \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_RUNNER_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${GITHUB_ORG}/actions/runners/registration-token" \
    | jq -r '.token')

  if [[ -z "${TOKEN}" ]] || [[ "${TOKEN}" == "null" ]]; then
    echo "ERROR: Failed to obtain registration token from GitHub API." >&2
    echo "       Check GITHUB_RUNNER_PAT has 'organization_self_hosted_runners: write' scope." >&2
    exit 1
  fi

  "${RUNNER_DIR}/config.sh" \
    --url "https://github.com/${GITHUB_ORG}" \
    --token "${TOKEN}" \
    --name "${RUNNER_NAME:-github-runner-noble}" \
    --labels "${RUNNER_LABELS:-self-hosted,linux}" \
    --unattended \
    --replace
  echo "==> Runner registered."
else
  echo "==> Runner already registered (${REG_FILE} exists), skipping config.sh."
fi

echo "==> Starting runner..."
exec "${RUNNER_DIR}/run.sh"
