#!/bin/bash
# FG-051: GitHub Actions self-hosted runner entrypoint.
#
# Behavior:
#   - Read GITHUB_ORG / GITHUB_RUNNER_PAT / RUNNER_NAME / RUNNER_LABELS env.
#   - If /home/runner/.runner does NOT exist: request a registration token
#     from the GitHub Actions API + run config.sh --unattended --replace.
#   - If /home/runner/.runner DOES exist: skip registration, go straight
#     to run.sh.
#   - Exec run.sh as PID 1 so docker signal handling works correctly.
#
# Matches the behavior of homelab's current docker/github-runner/
# entrypoint.sh (which this forge image replaces at deploy time per
# FG-051 scope).

set -euo pipefail

RUNNER_DIR="/home/runner"
REG_FILE="${RUNNER_DIR}/.runner"

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
