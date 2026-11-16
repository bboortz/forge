#!/bin/bash
# FG-051: GitHub Actions self-hosted runner entrypoint.
# FG-063: RUNNER_CREDS_DIR env var for narrow credential-volume deploys —
#         two-phase persistence (restart: pre-symlink; first-start: post-
#         config.sh move-into-creds-dir + symlink).
#
# Behavior:
#   - Read GITHUB_ORG / GITHUB_RUNNER_PAT / RUNNER_NAME / RUNNER_LABELS env.
#   - Read RUNNER_CREDS_DIR env (default /home/runner). When non-default,
#     the entrypoint persists credentials outside /home/runner so the
#     runner binary tree (/home/runner/bin/ + externals/) stays image-
#     layer owned and forge image bumps propagate every restart.
#     Two phases:
#       Phase 1 (restart): if RUNNER_CREDS_DIR/.runner already exists,
#         symlink the three credential files from /home/runner/ into
#         RUNNER_CREDS_DIR BEFORE invoking config.sh / run.sh. Note:
#         ONLY files that exist in the creds dir get a symlink —
#         pre-creating dangling symlinks for .credentials /
#         .credentials_rsaparams crashes Runner.Listener configure
#         because its LoadDefaultUserAgents() path follows the dangling
#         link and throws FileNotFoundException.
#       Phase 2 (first-start): no symlinks pre-created. config.sh writes
#         .runner / .credentials / .credentials_rsaparams natively into
#         /home/runner/. After config.sh completes, we move each regular
#         file into RUNNER_CREDS_DIR and replace it with a symlink —
#         persisting through the volume for next container startup.
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

# FG-063 Phase 1 (restart): if the creds dir already holds a .runner,
# this is a restart with persisted credentials — symlink every existing
# credential file into /home/runner/ so Runner.Listener reads through
# the symlinks. Files that DON'T yet exist in the creds dir (incomplete
# prior registration, GHE-only .credentials_rsaparams on github.com
# deploys) get NO symlink — a dangling symlink crashes
# Runner.Listener's LoadDefaultUserAgents() path.
if [[ "${RUNNER_CREDS_DIR}" != "${RUNNER_DIR}" ]]; then
  mkdir -p "${RUNNER_CREDS_DIR}"
  if [[ -f "${RUNNER_CREDS_DIR}/.runner" ]]; then
    for _f in .runner .credentials .credentials_rsaparams; do
      if [[ -f "${RUNNER_CREDS_DIR}/${_f}" ]]; then
        ln -sf "${RUNNER_CREDS_DIR}/${_f}" "${RUNNER_DIR}/${_f}"
      fi
    done
  fi
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

  # FG-063 Phase 2 (first-start post-config): move the freshly-written
  # credential files into RUNNER_CREDS_DIR and replace each with a
  # symlink so the next container start (potentially with a new forge
  # image layer via `docker compose up -d --pull always`) resolves
  # through the symlinks into the persistent volume.
  if [[ "${RUNNER_CREDS_DIR}" != "${RUNNER_DIR}" ]]; then
    for _f in .runner .credentials .credentials_rsaparams; do
      if [[ -f "${RUNNER_DIR}/${_f}" && ! -L "${RUNNER_DIR}/${_f}" ]]; then
        mv "${RUNNER_DIR}/${_f}" "${RUNNER_CREDS_DIR}/${_f}"
        ln -sf "${RUNNER_CREDS_DIR}/${_f}" "${RUNNER_DIR}/${_f}"
      fi
    done
    echo "==> Credentials persisted to ${RUNNER_CREDS_DIR}."
  fi
else
  echo "==> Runner already registered (${REG_FILE} exists), skipping config.sh."
fi

echo "==> Starting runner..."
exec "${RUNNER_DIR}/run.sh"
