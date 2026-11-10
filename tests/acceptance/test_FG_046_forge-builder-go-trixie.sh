#!/usr/bin/env bash
#
# Covers: FG-046
# CAPs:   build.shared-go-builder, build.from-go-source

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-046]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# Helper: extract the Go stdlib version embedded in a binary inside an image.
# Returns the first `go1.XX.YY` string found in the binary's data section.
image_go_stdlib() {
  local image="$1" bin="$2"
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" RETURN
  docker save "${image}" -o "${tmp}/i.tar"
  (cd "${tmp}" && tar xf i.tar) >/dev/null 2>&1
  python3 - "${tmp}" "${bin}" <<'PY'
import json, tarfile, pathlib, subprocess, sys, tempfile
root, binpath = sys.argv[1], sys.argv[2].lstrip('/')
m = json.loads(pathlib.Path(f"{root}/manifest.json").read_text())
for layer_file in m[0]['Layers']:
    lp = pathlib.Path(f"{root}/{layer_file}")
    try:
        with tarfile.open(lp) as t:
            if binpath in t.getnames():
                with tempfile.TemporaryDirectory() as td:
                    t.extract(binpath, td)
                    out = subprocess.check_output(['strings', f'{td}/{binpath}']).decode()
                    for line in out.split('\n'):
                        if line.startswith('go1.'):
                            print(line.split()[0])
                            sys.exit(0)
    except Exception:
        pass
sys.exit(1)
PY
}

say "1. forge-builder-go-trixie:0.1 builds + smokes pass"
bash scripts/build-image.sh forge-builder-go-trixie >/dev/null
for s in images/forge-builder-go-trixie/tests/smoke_*.sh; do
  bash "${s}" >/dev/null
done
pass "forge-builder-go-trixie:0.1 built + smokes green"

say "2. node-exporter-scratch-trixie: stdlib go1.27+ + version 1.9.0 preserved"
bash scripts/build-image.sh node-exporter-scratch-trixie >/dev/null
sv=$(image_go_stdlib "forge-local/node-exporter-scratch-trixie:1.9" /usr/bin/prometheus-node-exporter)
case "${sv}" in
  go1.2[7-9]*|go1.[3-9]*) ;;
  *) fail "node-exporter stdlib = '${sv}' (want go1.27+)" ;;
esac
pass "node-exporter stdlib = ${sv}"
out=$(docker run --rm forge-local/node-exporter-scratch-trixie:1.9 --version 2>&1 | head -1)
echo "${out}" | grep -q "node_exporter, version 1.9.0" \
  || fail "node-exporter --version unexpected: ${out}"
pass "node-exporter --version preserved"

say "3. alertmanager-scratch-trixie: stdlib go1.27+ + amtool preserved"
bash scripts/build-image.sh alertmanager-scratch-trixie >/dev/null
sv=$(image_go_stdlib "forge-local/alertmanager-scratch-trixie:0.28" /usr/bin/prometheus-alertmanager)
case "${sv}" in
  go1.2[7-9]*|go1.[3-9]*) ;;
  *) fail "alertmanager stdlib = '${sv}' (want go1.27+)" ;;
esac
pass "alertmanager stdlib = ${sv}"
docker run --rm --entrypoint=/usr/bin/amtool forge-local/alertmanager-scratch-trixie:0.28 --version >/dev/null 2>&1 \
  || fail "amtool missing or broken"
pass "amtool preserved"

say "4. ipmi-exporter-scratch-trixie: dual-builder + collector-override preserved"
bash scripts/build-image.sh ipmi-exporter-scratch-trixie >/dev/null
sv=$(image_go_stdlib "forge-local/ipmi-exporter-scratch-trixie:1.10" /usr/bin/prometheus-ipmi-exporter)
case "${sv}" in
  go1.2[7-9]*|go1.[3-9]*) ;;
  *) fail "ipmi-exporter (scratch) stdlib = '${sv}' (want go1.27+)" ;;
esac
pass "ipmi-exporter (scratch) stdlib = ${sv}"
IMAGE_TAG=1.10 bash images/ipmi-exporter-scratch-trixie/tests/smoke_ipmi_collector_uses_elf.sh >/dev/null \
  || fail "collector-override regression guard failed"
pass "collector-override regression guard still green"

say "5. ipmi-exporter-slim-trixie: stdlib go1.27+ + freeipmi preserved + shell preserved"
bash scripts/build-image.sh ipmi-exporter-slim-trixie >/dev/null
sv=$(image_go_stdlib "forge-local/ipmi-exporter-slim-trixie:1.10" /usr/bin/prometheus-ipmi-exporter)
case "${sv}" in
  go1.2[7-9]*|go1.[3-9]*) ;;
  *) fail "ipmi-exporter (slim) stdlib = '${sv}' (want go1.27+)" ;;
esac
pass "ipmi-exporter (slim) stdlib = ${sv}"
docker run --rm --entrypoint=/bin/sh forge-local/ipmi-exporter-slim-trixie:1.10 -c 'test -x /usr/sbin/ipmimonitoring && echo ok' \
  | grep -q "^ok$" || fail "ipmimonitoring missing in slim"
pass "ipmimonitoring + /bin/sh preserved in slim"

say "6. cadvisor-slim-trixie uses the shared Go base"
grep -q "FORGE_BUILDER_GO_REF" images/cadvisor-slim-trixie/Dockerfile \
  || fail "cadvisor Dockerfile doesn't reference FORGE_BUILDER_GO_REF"
grep -q "ARG GO_BASE=golang" images/cadvisor-slim-trixie/Dockerfile \
  && fail "cadvisor Dockerfile still has ARG GO_BASE=golang (should FROM forge-builder-go-trixie)"
sv=$(image_go_stdlib "forge-local/cadvisor-slim-trixie:0.60.6" /usr/bin/cadvisor)
case "${sv}" in
  go1.2[7-9]*|go1.[3-9]*) ;;
  *) fail "cadvisor stdlib = '${sv}' (want go1.27+)" ;;
esac
pass "cadvisor via shared Go base, stdlib = ${sv}"

say "7. zero Go-stdlib CRITICALs across every migrated image"
for img in forge-local/cadvisor-slim-trixie:0.60.6 \
           forge-local/node-exporter-scratch-trixie:1.9 \
           forge-local/alertmanager-scratch-trixie:0.28 \
           forge-local/ipmi-exporter-scratch-trixie:1.10 \
           forge-local/ipmi-exporter-slim-trixie:1.10; do
  crit=$(grype "${img}" -o json 2>/dev/null \
    | jq -r '.matches[] | select(.vulnerability.severity == "Critical" and .artifact.name == "stdlib") | .vulnerability.id' | sort -u)
  if [[ -n "${crit}" ]]; then
    fail "${img}: still has stdlib CRITICAL CVEs: ${crit}"
  fi
done
pass "all 5 migrated images: 0 stdlib CRITICAL CVEs"

say "8. prometheus migration is deferred (documented, not reverted)"
if ! grep -q "forge-builder-trixie:latest" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile no longer uses forge-builder-trixie — expected to be unchanged (deferred)"
fi
if ! grep -q "install prometheus" images/prometheus-scratch-trixie/Dockerfile; then
  fail "prometheus Dockerfile no longer apt-installs prometheus — expected to be unchanged (deferred)"
fi
grep -q "React UI\|npm" docs/plan/IDEAS.md \
  || fail "IDEAS.md doesn't document the prometheus React-UI-build-pipeline blocker"
pass "prometheus migration deferred + documented in IDEAS.md"

echo
echo "FG-046 acceptance: all sections passed."
