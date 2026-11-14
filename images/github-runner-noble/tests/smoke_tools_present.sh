#!/usr/bin/env bash
# Smoke — pre-baked CI toolset all responds.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-github-runner-noble}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Tools that respond to --version:
for tool in git curl jq make python3 pip3 shellcheck hadolint terraform; do
  docker run --rm --entrypoint="$(command -v env || echo /usr/bin/env)" "${IMAGE}" "${tool}" --version >/dev/null 2>&1 \
    || { echo "  ✗ ${tool} --version failed" >&2; exit 1; }
done
# unzip uses `-v` (not `--version`) — Info-ZIP convention.
docker run --rm --entrypoint=/usr/bin/unzip "${IMAGE}" -v >/dev/null 2>&1 \
  || { echo "  ✗ unzip -v failed" >&2; exit 1; }
echo "  ✓ git + curl + jq + unzip + make + python3 + pip3 + shellcheck + hadolint + terraform all respond"

# /bin/bash + /bin/sh presence (slim contract).
docker run --rm --entrypoint=/bin/bash "${IMAGE}" -c 'echo ok' | grep -qx ok
docker run --rm --entrypoint=/bin/sh "${IMAGE}" -c 'echo ok' | grep -qx ok
echo "  ✓ /bin/bash + /bin/sh present (slim contract)"

# hadolint version floor (bumped to upstream latest at ship time).
hadolint_v=$(docker run --rm --entrypoint=/usr/local/bin/hadolint "${IMAGE}" --version 2>&1)
case "${hadolint_v}" in
  *"Haskell Dockerfile Linter 2."*) echo "  ✓ hadolint: ${hadolint_v}" ;;
  *) echo "  ✗ unexpected hadolint version: ${hadolint_v}" >&2; exit 1 ;;
esac

# terraform version floor.
terraform_v=$(docker run --rm --entrypoint=/usr/local/bin/terraform "${IMAGE}" --version 2>&1 | head -1)
case "${terraform_v}" in
  *"Terraform v1."*) echo "  ✓ terraform: ${terraform_v}" ;;
  *) echo "  ✗ unexpected terraform version: ${terraform_v}" >&2; exit 1 ;;
esac
