#!/usr/bin/env bash
# Smoke — /entrypoint.sh honors RUNNER_CREDS_DIR env var (FG-063).
#
# Four sub-cases:
#  (a) Default (env unset): no symlinks are created in /home/runner —
#      behavior identical to pre-FG-063.
#  (b) Non-default + FRESH empty creds dir (first-start): NO symlinks
#      are pre-created. Pre-creating dangling symlinks for
#      .credentials / .credentials_rsaparams crashes Runner.Listener
#      configure's LoadDefaultUserAgents() path (regression test for
#      the fresh-volume crash).
#  (c) Non-default + pre-populated creds dir (restart case): symlinks
#      are created for every file that exists in the creds dir.
#      REG_FILE check short-circuits config.sh.
#  (d) Non-default + partially-populated creds dir (.runner present,
#      .credentials_rsaparams absent): the GHE-only rsaparams file
#      does NOT get a dangling symlink; .runner + .credentials do.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-github-runner-noble}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# -----------------------------------------------------------------------------
# (a) Default: RUNNER_CREDS_DIR unset. No symlinks created.
set +e
# shellcheck disable=SC2016  # inner "$(...)" must be expanded inside the container
default_out=$(timeout 15 docker run --rm --entrypoint=bash "${IMAGE}" -c \
  '/entrypoint.sh 2>&1 || true
   for f in .runner .credentials .credentials_rsaparams; do
     if [[ -L "/home/runner/${f}" ]]; then
       echo "SENTINEL_islink_${f}=YES"
     else
       echo "SENTINEL_islink_${f}=NO"
     fi
   done' 2>&1)
default_rc=$?
set -e
[[ ${default_rc} -eq 0 ]] || { echo "  ✗ (a) default-case docker run itself failed (rc=${default_rc}):" >&2; echo "${default_out}" >&2; exit 1; }
for f in .runner .credentials .credentials_rsaparams; do
  echo "${default_out}" | grep -q "SENTINEL_islink_${f}=NO" \
    || { echo "  ✗ (a) default-case: /home/runner/${f} was a symlink — expected NOT to be touched when RUNNER_CREDS_DIR is unset" >&2; echo "${default_out}" >&2; exit 1; }
done
echo "  ✓ (a) default RUNNER_CREDS_DIR: no symlinks created in /home/runner"

# -----------------------------------------------------------------------------
# (b) Non-default + FRESH empty creds dir. Expect NO symlinks (fixed the
# dangling-symlink crash: Runner.Listener configure follows a dangling
# .credentials symlink and throws FileNotFoundException).
host_dir_fresh="$(mktemp -d /tmp/forge-fg063-fresh-XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${host_dir_fresh}'" EXIT
set +e
# shellcheck disable=SC2016
fresh_out=$(timeout 15 docker run --rm \
  -e RUNNER_CREDS_DIR=/runner-creds \
  -v "${host_dir_fresh}:/runner-creds" \
  --entrypoint=bash "${IMAGE}" -c \
  '/entrypoint.sh 2>&1 || true
   for f in .runner .credentials .credentials_rsaparams; do
     if [[ -L "/home/runner/${f}" ]]; then
       echo "SENTINEL_islink_${f}=YES"
     else
       echo "SENTINEL_islink_${f}=NO"
     fi
   done' 2>&1)
fresh_rc=$?
set -e
[[ ${fresh_rc} -eq 0 ]] || { echo "  ✗ (b) fresh-volume docker run itself failed (rc=${fresh_rc}):" >&2; echo "${fresh_out}" >&2; exit 1; }
for f in .runner .credentials .credentials_rsaparams; do
  echo "${fresh_out}" | grep -q "SENTINEL_islink_${f}=NO" \
    || { echo "  ✗ (b) fresh-volume: /home/runner/${f} was a (dangling) symlink — must not be pre-created on first start" >&2; echo "${fresh_out}" >&2; exit 1; }
done
# Entrypoint must still have emitted the GITHUB_ORG error (fell through
# the symlink block + hit the env check).
echo "${fresh_out}" | grep -q 'GITHUB_ORG' \
  || { echo "  ✗ (b) fresh-volume: entrypoint did not reach the GITHUB_ORG env-missing error" >&2; echo "${fresh_out}" >&2; exit 1; }
echo "  ✓ (b) RUNNER_CREDS_DIR=/runner-creds + fresh volume: NO dangling symlinks pre-created (regression test)"

# -----------------------------------------------------------------------------
# (c) Non-default + pre-populated creds dir. All three credential files
# present → all three symlinked → REG_FILE check short-circuits config.sh.
host_dir_populated="$(mktemp -d /tmp/forge-fg063-populated-XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${host_dir_fresh}' '${host_dir_populated}'" EXIT
for f in .runner .credentials .credentials_rsaparams; do
  echo "fake-${f}-contents" > "${host_dir_populated}/${f}"
done
set +e
# shellcheck disable=SC2016
pop_out=$(timeout 15 docker run --rm \
  -e RUNNER_CREDS_DIR=/runner-creds \
  -v "${host_dir_populated}:/runner-creds" \
  --entrypoint=bash "${IMAGE}" -c \
  '/entrypoint.sh 2>&1 || true
   for f in .runner .credentials .credentials_rsaparams; do
     if [[ -L "/home/runner/${f}" ]]; then
       tgt=$(readlink "/home/runner/${f}")
       echo "SENTINEL_${f}=${tgt}"
     else
       echo "SENTINEL_${f}=NOT_A_SYMLINK"
     fi
   done' 2>&1)
pop_rc=$?
set -e
[[ ${pop_rc} -eq 0 ]] || { echo "  ✗ (c) populated-volume docker run itself failed (rc=${pop_rc}):" >&2; echo "${pop_out}" >&2; exit 1; }
for f in .runner .credentials .credentials_rsaparams; do
  echo "${pop_out}" | grep -q "SENTINEL_${f}=/runner-creds/${f}" \
    || { echo "  ✗ (c) populated-volume: /home/runner/${f} is not a symlink → /runner-creds/${f}" >&2; echo "${pop_out}" >&2; exit 1; }
done
# REG_FILE check should have fired: "Runner already registered ..., skipping config.sh"
echo "${pop_out}" | grep -q 'Runner already registered' \
  || { echo "  ✗ (c) populated-volume: entrypoint did not short-circuit config.sh" >&2; echo "${pop_out}" >&2; exit 1; }
echo "  ✓ (c) RUNNER_CREDS_DIR=/runner-creds + pre-populated: three symlinks created + config.sh short-circuited"

# -----------------------------------------------------------------------------
# (d) Non-default + partial creds dir. .runner + .credentials present,
# .credentials_rsaparams absent (github.com deploys don't use RSA).
# Expect: .runner + .credentials symlinked; .credentials_rsaparams NOT
# a symlink (would be dangling).
host_dir_partial="$(mktemp -d /tmp/forge-fg063-partial-XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${host_dir_fresh}' '${host_dir_populated}' '${host_dir_partial}'" EXIT
echo "fake-runner" > "${host_dir_partial}/.runner"
echo "fake-creds"  > "${host_dir_partial}/.credentials"
set +e
# shellcheck disable=SC2016
part_out=$(timeout 15 docker run --rm \
  -e RUNNER_CREDS_DIR=/runner-creds \
  -v "${host_dir_partial}:/runner-creds" \
  --entrypoint=bash "${IMAGE}" -c \
  '/entrypoint.sh 2>&1 || true
   for f in .runner .credentials .credentials_rsaparams; do
     if [[ -L "/home/runner/${f}" ]]; then
       echo "SENTINEL_islink_${f}=YES"
     else
       echo "SENTINEL_islink_${f}=NO"
     fi
   done' 2>&1)
part_rc=$?
set -e
[[ ${part_rc} -eq 0 ]] || { echo "  ✗ (d) partial-volume docker run itself failed (rc=${part_rc}):" >&2; echo "${part_out}" >&2; exit 1; }
echo "${part_out}" | grep -q 'SENTINEL_islink_.runner=YES' \
  || { echo "  ✗ (d) partial-volume: /home/runner/.runner must be a symlink" >&2; echo "${part_out}" >&2; exit 1; }
echo "${part_out}" | grep -q 'SENTINEL_islink_.credentials=YES' \
  || { echo "  ✗ (d) partial-volume: /home/runner/.credentials must be a symlink" >&2; echo "${part_out}" >&2; exit 1; }
echo "${part_out}" | grep -q 'SENTINEL_islink_.credentials_rsaparams=NO' \
  || { echo "  ✗ (d) partial-volume: /home/runner/.credentials_rsaparams must NOT be a (dangling) symlink" >&2; echo "${part_out}" >&2; exit 1; }
echo "  ✓ (d) RUNNER_CREDS_DIR=/runner-creds + partial creds: only existing files symlinked (no dangling rsaparams)"
