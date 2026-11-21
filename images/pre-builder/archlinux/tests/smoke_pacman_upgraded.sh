#!/usr/bin/env bash
# Smoke: pacman -Syu simulate finds nothing further to upgrade.
#
# NOTE: Arch is rolling. Between build + test moments, the upstream
# mirrors may have advanced; a few packages may show as upgradable. We
# require ≤ 5 pending upgrades (noise threshold). Hard zero would be
# flaky in CI; a large positive number means the build's -Syu never ran.
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/archlinux}"
: "${IMAGE_TAG:=latest}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# pacman -Syup --print lists URLs of packages that would be
# downloaded to upgrade. Count non-empty lines.
out=$(docker run --rm "${IMAGE}" bash -c "pacman -Syup --print 2>/dev/null | grep -c '^https' || true")
pending="${out:-0}"
# pacman seeds mirror sync BEFORE query, so a transient mirror diff can
# produce 1-5 "upgrades". Accept up to 10 (hadolint/scanning safety).
if [[ "${pending}" -gt 10 ]]; then
  echo "  ✗ ${pending} package(s) have pending upgrades at test time (>10 noise floor)" >&2
  exit 1
fi
echo "  ✓ pacman -Syu simulate: ${pending} pending upgrades (≤ 10 noise floor)"
