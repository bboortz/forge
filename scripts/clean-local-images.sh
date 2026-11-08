#!/usr/bin/env bash
# Remove every forge-local/* docker image so `make check-strict` starts from
# an empty local image set. Scoped — does NOT touch anything outside the
# forge-local/ namespace. Fast (nothing to rebuild if nothing was cached).
#
# Catches the failure mode from PR #7 CI: a stale IMAGE_REPO value in a
# test was referencing forge-local/python:3.14-slim-trixie, which no longer
# matches any image recipe in the repo. The workstation had the old image
# cached from a pre-FG-004 build, so `docker run` found it and the test
# passed locally; the clean CI runner failed. Clearing forge-local/* forces
# every test to resolve its image reference against something the current
# Makefile + scripts actually produce.

set -euo pipefail

mapfile -t ids < <(docker images --format '{{.Repository}} {{.ID}}' \
                   | awk '$1 ~ /^forge-local\//{print $2}' \
                   | sort -u)

if [[ ${#ids[@]} -eq 0 ]]; then
  echo "clean-local-images: no forge-local/* images to remove"
  exit 0
fi

docker rmi -f "${ids[@]}" >/dev/null 2>&1 || true
echo "clean-local-images: removed ${#ids[@]} forge-local/* image(s)"
