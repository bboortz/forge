#!/usr/bin/env bash
# Smoke — pg_dumpall (and other popen()-using client tools) cannot run
# standalone in postgres-scratch-trixie because /bin/sh is absent.
#
# This smoke LOCKS IN the current behavior documented on the image's
# absence.shell PROMISE. It should FAIL if a future change accidentally
# makes pg_dumpall succeed here (e.g. a shell lands in the baseline) —
# that would silently invalidate the no-shell differentiator and should
# be caught + re-evaluated as a deliberate design decision.
#
# The failure mode under test: pg_dumpall calls pipe_read_line() →
# popen("\"/usr/lib/postgresql/18/bin/pg_dump\" -V", "r") → /bin/sh -c ...
# → ENOENT on /bin/sh. Postgres emits a cryptic error that names pg_dump
# as "not found in the same directory as pg_dumpall" — the error message
# is wrong (pg_dump IS at that path), the real failure is on /bin/sh.
#
# For workflows that need pg_dumpall / initdb / pg_amcheck, use the
# sibling image postgres-slim-trixie:18 (FG-026), which is based on
# Docker Hub's `postgres:18` + apt-upgrade and has a shell.

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-postgres-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-18}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Direct --version on pg_dumpall MUST succeed — the binary + its lib
# closure are fine. This is the control case proving that "pg_dump not
# found" error is a misdiagnosis of a missing /bin/sh.
if ! docker run --rm \
     --entrypoint=/usr/lib/postgresql/18/bin/pg_dumpall \
     "${IMAGE}" --version >/dev/null 2>&1; then
  echo "  ✗ pg_dumpall --version failed — unexpected (binary or lib closure is broken)" >&2
  exit 1
fi

# pg_dumpall invoked against a real(-ish) target: it calls pg_dump -V
# via popen BEFORE opening any socket, so we don't need an actual
# server. The invocation MUST fail and the stderr MUST match the
# documented error signature.
set +e
out=$(docker run --rm \
      --entrypoint=/usr/lib/postgresql/18/bin/pg_dumpall \
      "${IMAGE}" -h 127.0.0.1 -U nobody 2>&1)
rc=$?
set -e

if [[ ${rc} -eq 0 ]]; then
  echo "  ✗ pg_dumpall unexpectedly succeeded in scratch (no /bin/sh)" >&2
  echo "    This means a shell has leaked into the image — re-evaluate" >&2
  echo "    the absence.shell PROMISE before shipping." >&2
  echo "    Captured output:" >&2
  echo "${out}" >&2
  exit 1
fi

# The misleading error signature we document on absence.shell:
if ! grep -q 'program "pg_dump" is needed by pg_dumpall' <<< "${out}"; then
  echo "  ✗ pg_dumpall failure mode changed — no longer prints the" >&2
  echo "    documented 'program pg_dump is needed by pg_dumpall' error." >&2
  echo "    Update the absence.shell PROMISE description accordingly." >&2
  echo "    Captured output:" >&2
  echo "${out}" >&2
  exit 1
fi

echo "  ✓ pg_dumpall --version works standalone (binary OK)"
echo "  ✓ pg_dumpall end-to-end fails with the documented 'pg_dump not found'"
echo "    error — real cause is missing /bin/sh (popen target). Use"
echo "    postgres-slim-trixie:18 (FG-026) for pg_dumpall workflows."
