#!/usr/bin/env bash
#
# Covers: FG-016
# CAPs:   image.nginx-serves-http, contracts.promises, contracts.semver-enforcement
#
# Validates that nginx-scratch-trixie bundles dynamic modules + mime.types
# so stream-based consumers (sni-router) can mount their own config without
# building a derived image.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say() { printf '\n\033[1;36m[FG-016]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

IMAGE="forge-local/nginx-scratch-trixie:1.26"

say "1. build nginx-scratch-trixie"
bash scripts/build-image.sh nginx-scratch-trixie >/dev/null
docker image inspect "${IMAGE}" >/dev/null
pass "${IMAGE} built"

say "2. modules + mime.types bundled"
bash images/nginx-scratch-trixie/tests/smoke_modules_present.sh
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"
paths_file="${tmp}/all_paths.txt"
for layer in "${tmp}"/blobs/sha256/*; do
  tar tf "${layer}" 2>/dev/null || true
done | sort -u > "${paths_file}"
grep -qxF 'etc/nginx/mime.types' "${paths_file}" \
  || { echo "  ✗ /etc/nginx/mime.types missing" >&2; exit 1; }
pass "/etc/nginx/mime.types present"

say "3. sni-router-shape config passes nginx -t"
bash images/nginx-scratch-trixie/tests/smoke_stream_config_validates.sh

say "4. no regression — default config still serves HTTP 200"
bash images/nginx-scratch-trixie/tests/smoke_serves_200.sh >/dev/null
pass "default welcome page unaffected"

say "5. PROMISES.yaml version bumped (0.1 → 0.2) + semver gate accepts the add"
ver=$(python3 -c "import yaml; print(yaml.safe_load(open('images/nginx-scratch-trixie/PROMISES.yaml'))['version'])")
case "${ver}" in
  0.2|0.2.*|0.[3-9]*|[1-9]*) pass "version is ${ver}" ;;
  *) echo "  ✗ version is ${ver}, expected ≥ 0.2" >&2; exit 1 ;;
esac

# Replay the semver gate for the 0.1 → 0.2 add
cp images/nginx-scratch-trixie/PROMISES.yaml "${tmp}/new.yaml"
python3 - "${tmp}/new.yaml" "${tmp}/old.yaml" <<'PY'
import sys, yaml, pathlib
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(pathlib.Path(src).read_text())
data['promises'] = [p for p in data['promises'] if p['id'] != 'runtime.dynamic-modules']
data['version'] = '0.1'
pathlib.Path(dst).write_text(yaml.safe_dump(data, sort_keys=False))
PY
python3 scripts/contracts-semver-check.py --compare "${tmp}/old.yaml" "${tmp}/new.yaml" >/dev/null
pass "semver gate accepts 0.1 → 0.2 bump for the add"

say "6. verify-contracts stays green with the new promise"
python3 scripts/verify-contracts.py >/dev/null
pass "verify-contracts: ok"

if [[ "${PUBLISHED:-0}" == "1" ]]; then
  say "7. published digest check"
  docker pull ghcr.io/bboortz/nginx-scratch-trixie:1.26 >/dev/null
  docker run --rm --entrypoint=/usr/sbin/nginx ghcr.io/bboortz/nginx-scratch-trixie:1.26 -V 2>&1 | grep -q 'stream_ssl_preread'
  pass "ghcr.io/bboortz/nginx-scratch-trixie:1.26 has stream_ssl_preread compiled"
else
  say "7. published-digest checks skipped (set PUBLISHED=1 to run)"
fi

echo
echo "FG-016 acceptance: all sections passed."
