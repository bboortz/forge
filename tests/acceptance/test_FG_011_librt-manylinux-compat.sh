#!/usr/bin/env bash
#
# Covers: FG-011
# CAPs:   image.manylinux-wheel-compat, image.python-scratch-nonroot,
#         test.image-smoke-suite, contracts.promises
#
# python-scratch-trixie ships the librt.so.1 ABI stub so manylinux2014 /
# manylinux_2_17 wheels (numpy, scipy, pandas, pillow, cryptography)
# dlopen successfully at runtime. glibc 2.34 merged librt into libc;
# the 14.5 KB stub Debian still ships is what satisfies NEEDED librt.so.1
# in those wheels.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-011]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/python-scratch-trixie:3.13"

# -----------------------------------------------------------------------------
# Section 1 — build python-scratch-trixie with the librt addition
# -----------------------------------------------------------------------------
say "1. python-scratch-trixie builds"
bash scripts/build-image.sh python-scratch-trixie >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

# -----------------------------------------------------------------------------
# Section 2 — smoke_librt_manylinux passes (presence + runtime dlopen)
# -----------------------------------------------------------------------------
say "2. librt.so.1 is present AND dlopen-able"
bash images/python-scratch-trixie/tests/smoke_librt_manylinux.sh

# -----------------------------------------------------------------------------
# Section 3 — PROMISES.yaml reflects the new guarantee + bump
# -----------------------------------------------------------------------------
say "3. PROMISES.yaml declares runtime.librt-abi-stub @ version 0.2+"
grep -q 'id: runtime.librt-abi-stub' images/python-scratch-trixie/PROMISES.yaml \
  || { echo "✗ promise id missing" >&2; exit 1; }
grep -q 'smoke_librt_manylinux.sh' images/python-scratch-trixie/PROMISES.yaml \
  || { echo "✗ smoke pointer missing" >&2; exit 1; }
ver=$(python3 -c "import yaml, sys; print(yaml.safe_load(open('images/python-scratch-trixie/PROMISES.yaml'))['version'])")
case "${ver}" in
  0.2|0.2.*|0.[3-9]*|[1-9]*)
    pass "version is ${ver} (≥ 0.2 — minor bump from 0.1)"
    ;;
  *)
    echo "✗ version is ${ver}, expected ≥ 0.2 (minor bump from 0.1)" >&2
    exit 1
    ;;
esac

# -----------------------------------------------------------------------------
# Section 4 — verify-contracts stays green
# -----------------------------------------------------------------------------
say "4. verify-contracts is green with the new promise"
python3 scripts/verify-contracts.py >/dev/null
pass "verify-contracts: ok"

# -----------------------------------------------------------------------------
# Section 5 — semver gate accepts the version bump
# -----------------------------------------------------------------------------
say "5. semver gate accepts 0.1 → 0.2 bump for the add"
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
# Snapshot "old" by removing the new promise + reverting version
python3 - images/python-scratch-trixie/PROMISES.yaml "${tmp}/old.yaml" <<'PY'
import sys, yaml, pathlib
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(pathlib.Path(src).read_text())
data['promises'] = [p for p in data['promises'] if p['id'] != 'runtime.librt-abi-stub']
data['version'] = '0.1'
pathlib.Path(dst).write_text(yaml.safe_dump(data, sort_keys=False))
PY
python3 scripts/contracts-semver-check.py --compare "${tmp}/old.yaml" images/python-scratch-trixie/PROMISES.yaml >/dev/null
pass "semver gate: ok on this exact 0.1 → 0.2 add"

# -----------------------------------------------------------------------------
# Section 6 — Post-publish (opt-in via PUBLISHED=1)
# -----------------------------------------------------------------------------
if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "6. published digest ships the stub"
  docker run --rm --entrypoint=/usr/local/bin/python3 \
    ghcr.io/bboortz/python-scratch-trixie:3.13 \
    -c "import ctypes; ctypes.CDLL('librt.so.1'); print('ok')" \
    | grep -qx ok
  pass "ghcr.io/bboortz/python-scratch-trixie:3.13 dlopens librt.so.1"
else
  say "6. published-digest check skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-011 acceptance: all sections passed."
