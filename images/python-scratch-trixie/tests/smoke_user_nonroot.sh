#!/usr/bin/env bash
# Smoke — python-scratch-trixie runs as uid 65532 (nonroot) by default.
#
# Catches regressions on USER directive (consumer silently running as root
# is a recurring security bug — one typo or dropped USER line and the
# container escalates). FG-009 pins uid 65532; this test is the guard.
#
# Delivers: FG-009 Scenario "python-scratch defaults to USER 65532".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.13}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 1. docker inspect-level check — User field is baked into the image config.
got=$(docker image inspect "${IMAGE}" --format '{{.Config.User}}')
if [[ "${got}" != "65532:65532" ]]; then
  echo "  ✗ .Config.User is '${got}', expected '65532:65532'" >&2
  exit 1
fi

# 2. Runtime check — python actually reports uid 65532.
got_uid=$(docker run --rm "${IMAGE}" \
  -c "import os; print(f'{os.geteuid()}:{os.getegid()}')")
if [[ "${got_uid}" != "65532:65532" ]]; then
  echo "  ✗ process runs as '${got_uid}', expected '65532:65532'" >&2
  exit 1
fi

# 3. Runtime check — HOME resolves to /nonroot via the nonroot passwd entry.
got_home=$(docker run --rm "${IMAGE}" \
  -c "import pwd, os; print(pwd.getpwuid(os.geteuid()).pw_dir)")
if [[ "${got_home}" != "/nonroot" ]]; then
  echo "  ✗ HOME lookup returned '${got_home}', expected '/nonroot'" >&2
  exit 1
fi

echo "  ✓ default USER 65532:65532, HOME /nonroot (inspect + runtime)"
