#!/usr/bin/env bash
# Smoke — ansible + the vendored collections (ansible.posix +
# community.general) are pre-installed.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-github-runner-noble}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# ansible core.
docker run --rm --entrypoint=/usr/bin/env "${IMAGE}" ansible --version >/dev/null 2>&1 \
  || { echo "  ✗ ansible --version failed" >&2; exit 1; }
echo "  ✓ ansible --version responds"

# ansible-galaxy collection list → must include both collections.
collections=$(docker run --rm --entrypoint=/usr/bin/env "${IMAGE}" ansible-galaxy collection list 2>&1)
echo "${collections}" | grep -q 'ansible.posix' \
  || { echo "  ✗ ansible.posix collection not installed" >&2; echo "${collections}" >&2; exit 1; }
echo "${collections}" | grep -q 'community.general' \
  || { echo "  ✗ community.general collection not installed" >&2; echo "${collections}" >&2; exit 1; }
echo "  ✓ ansible.posix + community.general collections pre-installed"

# Vendored pip deps: ansible-lint + ruff + yamllint + pytest all respond.
for tool in ansible-lint ruff yamllint pytest; do
  docker run --rm --entrypoint=/usr/bin/env "${IMAGE}" "${tool}" --version >/dev/null 2>&1 \
    || { echo "  ✗ ${tool} --version failed" >&2; exit 1; }
done
echo "  ✓ ansible-lint + ruff + yamllint + pytest all respond (homelab vendored deps)"
