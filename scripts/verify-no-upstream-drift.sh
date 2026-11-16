#!/usr/bin/env bash
# verify-no-upstream-drift (FG-042 follow-up).
#
# FG-042 collapsed the two multi-consumer Docker Hub trust anchors
# (python:3.14-slim-trixie + debian:trixie-slim) behind forge-rooted
# pre-builder images (python-slim-trixie + debian-slim-trixie). Every
# downstream slim consumer FROMs the forge pre-builder, not the upstream
# Docker Hub image directly. That invariant is only valuable if we
# catch future drift FAST — a new Dockerfile that FROMs the upstream
# directly re-opens the version-drift risk.
#
# This script is the pre-commit guard (FG-042's acceptance test §7 is
# the CI guard; this one fires at commit time, ~100 ms vs CI's ~5 min).
#
# Rule: `^FROM debian:trixie-slim` and `^FROM python:3.14-slim-trixie`
# are allowed in exactly 2 Dockerfiles total — the two pre-builders
# themselves. Any other hit means a downstream image bypassed the
# forge-signed intermediate.
#
# To extend the invariant to a new upstream anchor (e.g. after
# shipping node-slim-trixie or postgres-slim-trixie-base), add the
# upstream tag to _UPSTREAM_ANCHORS below + bump _EXPECTED to the
# number of forge pre-builders that should carry it. The test
# intentionally fails on under-count AND over-count: an added entry
# with no corresponding pre-builder means the anchor is still
# freely consumed; a missing entry means something regressed.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Upstream Docker Hub tags that MUST go through a forge pre-builder.
_UPSTREAM_ANCHORS=(
  'debian:trixie-slim'
  'debian:sid-slim'
  'python:3\.14-slim-trixie'
  'ubuntu:24\.04'
  'node:24-trixie-slim'
)
# How many Dockerfiles SHOULD FROM each anchor (= how many pre-builders
# each anchor should feed into). FG-061 adds node-slim-trixie as the
# 5th pre-builder using a LITERAL `FROM node:24-trixie-slim` line.
# forge-builder-node-trixie also uses this base but via ARG-indirect
# (`FROM ${NODE_BASE}`), which the grep below doesn't match — that's
# the dedicated-toolchain exemption, same pattern as forge-builder-
# go-trixie with `golang:1.27-trixie`.
_EXPECTED=5

# Build a single alternation for grep (|-separated).
_ANCHOR_RE="$(IFS='|'; echo "${_UPSTREAM_ANCHORS[*]}")"

hits=$(grep -lE "^FROM (${_ANCHOR_RE})" images/*/Dockerfile 2>/dev/null | wc -l)

if [[ "${hits}" -ne "${_EXPECTED}" ]]; then
  printf '✗ verify-no-upstream-drift: expected %d Dockerfiles FROMing ' "${_EXPECTED}" >&2
  printf 'the upstream Docker Hub anchors, got %d:\n' "${hits}" >&2
  echo >&2
  grep -lE "^FROM (${_ANCHOR_RE})" images/*/Dockerfile 2>/dev/null \
    | sed 's/^/  /' >&2
  echo >&2
  echo "FG-042 invariant: upstream Docker Hub anchors must be consumed" >&2
  echo "by exactly one forge pre-builder (debian-slim-trixie, debian-" >&2
  echo "slim-sid, python-slim-trixie, ubuntu-slim-noble, node-slim-" >&2
  echo "trixie). If you need a new slim image rooted on any of those" >&2
  echo "upstreams, FROM the forge pre-builder instead of the upstream" >&2
  echo "Docker Hub tag." >&2
  exit 1
fi

echo "✓ verify-no-upstream-drift: ${hits} Dockerfiles FROM upstream (= expected ${_EXPECTED} pre-builders)"
