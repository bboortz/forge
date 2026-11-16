#!/usr/bin/env bash
# Smoke — /entrypoint.sh honors RUNNER_CREDS_DIR env var (FG-063).
#
# Two sub-cases:
#  (a) Default (env unset): no symlinks are created in /home/runner —
#      behavior identical to pre-FG-063.
#  (b) Non-default (env=/runner-creds): three credential symlinks are
#      created in /home/runner pointing into /runner-creds, BEFORE
#      the entrypoint short-circuits on the missing GITHUB_ORG check.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-github-runner-noble}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# -----------------------------------------------------------------------------
# (a) Default: RUNNER_CREDS_DIR unset. Entrypoint fails on missing GITHUB_ORG
# BUT must NOT have created any symlinks in /home/runner (the default-path
# branch is a no-op). Validate by overriding entrypoint to `bash -c "..."`
# that runs the real entrypoint AND then prints the readlink of the three
# dotfiles afterwards.
set +e
# shellcheck disable=SC2016  # inner "$(...)" must be expanded inside the container, not here
default_out=$(timeout 15 docker run --rm --entrypoint=bash "${IMAGE}" -c \
  '/entrypoint.sh 2>&1 || true
   printf "SENTINEL_%s=%s\n" dot_runner "$(readlink -m /home/runner/.runner 2>/dev/null || echo NOSYMLINK)"
   printf "SENTINEL_%s=%s\n" dot_creds  "$(readlink -m /home/runner/.credentials 2>/dev/null || echo NOSYMLINK)"
   printf "SENTINEL_%s=%s\n" dot_rsa    "$(readlink -m /home/runner/.credentials_rsaparams 2>/dev/null || echo NOSYMLINK)"
   # Also confirm they are not symlinks via -L (readlink -m resolves and
   # returns the path even if the file does not exist, so we also test
   # -L which is true only for actual symlinks).
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
# (b) Non-default: RUNNER_CREDS_DIR=/runner-creds. The entrypoint should
# mkdir the target + create three symlinks in /home/runner pointing at
# /runner-creds/<dotfile>, THEN proceed to the GITHUB_ORG check (which
# will fail with its normal error because GITHUB_ORG is unset).
host_dir="$(mktemp -d /tmp/forge-fg063-XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '${host_dir}'" EXIT
set +e
# shellcheck disable=SC2016  # inner "$(...)" must be expanded inside the container, not here
nondef_out=$(timeout 15 docker run --rm \
  -e RUNNER_CREDS_DIR=/runner-creds \
  -v "${host_dir}:/runner-creds" \
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
nondef_rc=$?
set -e
[[ ${nondef_rc} -eq 0 ]] || { echo "  ✗ (b) non-default-case docker run itself failed (rc=${nondef_rc}):" >&2; echo "${nondef_out}" >&2; exit 1; }
for f in .runner .credentials .credentials_rsaparams; do
  echo "${nondef_out}" | grep -q "SENTINEL_${f}=/runner-creds/${f}" \
    || { echo "  ✗ (b) non-default-case: /home/runner/${f} is not a symlink → /runner-creds/${f}" >&2; echo "${nondef_out}" >&2; exit 1; }
done
# Entrypoint must still have emitted the standard GITHUB_ORG error — proves
# the symlink block ran BEFORE the env check short-circuit.
echo "${nondef_out}" | grep -q 'GITHUB_ORG' \
  || { echo "  ✗ (b) entrypoint did not reach / emit the GITHUB_ORG env-missing error" >&2; echo "${nondef_out}" >&2; exit 1; }
echo "  ✓ (b) RUNNER_CREDS_DIR=/runner-creds: three symlinks created + GITHUB_ORG check still fires"
