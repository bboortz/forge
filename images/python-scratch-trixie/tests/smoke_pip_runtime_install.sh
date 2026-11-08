#!/usr/bin/env bash
# Smoke — pip can actually install a wheel at runtime (not just dry-run).
# Installs `requests` into /tmp/pkg inside the container, then imports it.
# Exercises the real TLS + CA bundle + pip resolver + site-packages write
# path; catches issues that --dry-run doesn't.
#
# FG-009: variant has ENTRYPOINT=python3 + USER 65532; /tmp is 1777 so
# nonroot can write to /tmp/pkg.
#
# Delivers: FG-003 Scenario "pip install works at runtime for wheels".
#
# Network-dependent: requires outbound HTTPS to PyPI. Known-flaky on blipped
# networks; accepted trade-off because this is the only test that catches
# actual-install regressions (and transitively verifies SSL_CERT_FILE is
# effective — pip's TLS to PyPI would fail without it).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker run --rm --entrypoint=python3 "${IMAGE}" -c "
import subprocess, sys, importlib
subprocess.check_call([
    'pip', 'install', '--quiet', '--disable-pip-version-check',
    '--target', '/tmp/pkg', 'requests',
])
sys.path.insert(0, '/tmp/pkg')
mod = importlib.import_module('requests')
assert hasattr(mod, '__version__'), 'requests imported but has no __version__'
print(f'requests {mod.__version__}')
" >/dev/null
echo "  ✓ pip install --target requests + import round-trips"
