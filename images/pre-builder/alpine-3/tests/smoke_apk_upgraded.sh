#!/usr/bin/env bash
# Smoke: apk upgrade finds nothing further to upgrade (freshness proxy).
set -euo pipefail

: "${IMAGE_NAME:=pre-builder/alpine-3}"
: "${IMAGE_TAG:=3}"
: "${REGISTRY:=forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# `apk upgrade --simulate --no-cache` lists what WOULD be upgraded; should
# be empty (modulo transient upstream apk index diffs).
out=$(docker run --rm "${IMAGE}" apk upgrade --simulate --no-cache 2>&1 || true)
# Look for "Upgrading" lines (non-null counts of upgrades pending).
pending=$(echo "${out}" | grep -c "^Upgrading" || true)
if [[ "${pending}" -gt 0 ]]; then
  echo "  ✗ ${pending} package(s) have pending upgrades at build time:" >&2
  echo "${out}" | grep "^Upgrading" | head -5 >&2
  exit 1
fi
echo "  ✓ apk upgrade --simulate shows no pending upgrades"
