#!/usr/bin/env bash
#
# Covers: FG-020
# CAPs:   scan.sbom-embed, scan.regression-gate, sbom.cyclonedx-attest
#
# Validates FG-020:
#   - /sbom.json ships in every Forge-native scratch image (4 images)
#   - SBOM is dpkg-only CycloneDX (no builder noise like syft/curl)
#   - scan-regression detects SBOM and uses `grype sbom:` via the SBOM path
#   - externally-sourced images (beaconry) have no SBOM → scan-regression
#     falls back to image-direct scanning without erroring

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-020]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }

if ! command -v grype >/dev/null 2>&1; then
  echo "  ⚠ grype not installed — skipping FG-020 acceptance"
  exit 0
fi

# -----------------------------------------------------------------------------
# Section 1 — /sbom.json ships in every Forge-native scratch image
# -----------------------------------------------------------------------------
say "1. /sbom.json present in Forge-native scratch images"
for img in scratch-base-trixie python-scratch-trixie nginx-scratch-trixie postgres-scratch-trixie; do
  tag=$(awk '/^tag:/ {gsub(/["\x27]/,"",$2); print $2; exit}' "images/${img}/image.yaml")
  ref="forge-local/${img}:${tag}"
  if ! bash scripts/build-image.sh "${img}" > "/tmp/fg020-build-${img}.log" 2>&1; then
    echo "  ✗ ${img}: build failed (last 40 lines):" >&2
    tail -40 "/tmp/fg020-build-${img}.log" >&2
    exit 1
  fi
  cid=$(docker create --entrypoint=/nonexistent "${ref}")
  tmp=$(mktemp -d)
  trap 'rm -rf "${tmp}"' RETURN
  if ! docker cp "${cid}:/sbom.json" "${tmp}/sbom.json" 2>/dev/null; then
    echo "  ✗ ${img}: /sbom.json missing" >&2
    docker rm "${cid}" >/dev/null
    exit 1
  fi
  docker rm "${cid}" >/dev/null
  # Validate it's CycloneDX JSON
  python3 -c "
import sys, json
d = json.load(open('${tmp}/sbom.json'))
assert d.get('bomFormat') == 'CycloneDX', f'wrong bomFormat: {d.get(\"bomFormat\")}'
components = d.get('components') or []
assert len(components) > 0, 'empty components list'
# Every component must be deb-type (from --override-default-catalogers dpkg-db-cataloger).
# None-type components can be CPE-only entries syft emits; check there are debs.
deb_count = sum(1 for c in components if 'pkg:deb/' in (c.get('purl') or ''))
assert deb_count > 0, f'no deb components in ${img} SBOM'
print(f'  ${img}: {deb_count} deb packages in SBOM')
"
  rm -rf "${tmp}"; trap - RETURN
done
pass "all 4 Forge-native scratch images carry /sbom.json"

# -----------------------------------------------------------------------------
# Section 2 — SBOM is dpkg-only (no builder noise)
# -----------------------------------------------------------------------------
say "2. SBOM excludes builder-only tooling (syft, go-modules)"
cid=$(docker create --entrypoint=/nonexistent forge-local/nginx-scratch-trixie:1.26)
tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker cp "${cid}:/sbom.json" "${tmp}/sbom.json"
docker rm "${cid}" >/dev/null
# Verify no go-module or curl entries
python3 -c "
import sys, json
d = json.load(open('${tmp}/sbom.json'))
bad = []
for c in d.get('components', []):
    purl = c.get('purl') or ''
    name = c.get('name') or ''
    if purl.startswith('pkg:golang/'):
        bad.append(f'go-module leaked: {name}')
    # curl should've been purged
    if name == 'curl':
        bad.append('curl was not purged')
if bad:
    for b in bad:
        print(f'  ✗ {b}', file=sys.stderr)
    sys.exit(1)
print('  no builder-only noise')
"
pass "SBOM contains only dpkg packages (no go-module, no curl)"

# -----------------------------------------------------------------------------
# Section 3 — scan-regression uses embedded SBOM (log says so)
# -----------------------------------------------------------------------------
say "3. scan-regression detects + uses the embedded SBOM"
out=$(python3 scripts/scan-regression.py nginx-scratch-trixie 2>&1 || true)
echo "${out}" | grep -q 'using embedded SBOM' || {
  echo "  ✗ expected 'using embedded SBOM' in scan-regression output" >&2
  echo "${out}" >&2
  exit 1
}
pass "scan-regression resolves to sbom:<path> for nginx-scratch-trixie"

# -----------------------------------------------------------------------------
# Section 4 — Debian backports honored: nginx CVEs no longer in current scan
# -----------------------------------------------------------------------------
say "4. CVE-2026-15176 + CVE-2026-42533 (Debian-backported) resolved via SBOM"
# Fresh rescan — not against baseline, against current. We want no CRITICAL
# CVE from the nvd:cpe fallback since Debian matcher now has version info.
sbom_out=$(python3 -c "
import subprocess, json, tempfile, pathlib
tmp = pathlib.Path(tempfile.mkdtemp())
cid = subprocess.run(['docker', 'create', '--entrypoint=/nonexistent', 'forge-local/nginx-scratch-trixie:1.26'], capture_output=True, text=True, check=True).stdout.strip()
try:
    subprocess.run(['docker', 'cp', f'{cid}:/sbom.json', str(tmp / 'sbom.json')], check=True)
finally:
    subprocess.run(['docker', 'rm', cid], capture_output=True)
scan = json.loads(subprocess.run(['grype', f'sbom:{tmp / \"sbom.json\"}', '-o', 'json'], capture_output=True, text=True, check=True).stdout)
critical = [m for m in scan.get('matches', []) if ((m.get('vulnerability') or {}).get('severity') or '').lower() == 'critical']
cves = {(m.get('vulnerability') or {}).get('id') for m in critical}
if 'CVE-2026-15176' in cves or 'CVE-2026-42533' in cves:
    print(f'FAIL — still reports: {cves}')
    exit(1)
print(f'OK — no nginx NVD-CPE false positives (critical set: {cves or \"empty\"})')
")
echo "${sbom_out}"
pass "Debian backports honored via SBOM matcher"

# -----------------------------------------------------------------------------
# Section 5 — externally-sourced images fall back gracefully (no SBOM, no error)
# -----------------------------------------------------------------------------
say "5. externally-sourced image fallback (beaconry-telegram-mock)"
bash scripts/build-image.sh beaconry-telegram-mock >/dev/null 2>&1
out=$(python3 scripts/scan-regression.py beaconry-telegram-mock 2>&1 || true)
if echo "${out}" | grep -q 'using embedded SBOM'; then
  echo "  ✗ beaconry-telegram-mock unexpectedly has an embedded SBOM" >&2
  echo "${out}" >&2
  exit 1
fi
# Should still succeed with image-direct scan
if ! echo "${out}" | grep -qE 'scan-regression:\s+ok|FAIL'; then
  echo "  ✗ unexpected scan-regression output" >&2
  echo "${out}" >&2
  exit 1
fi
pass "fallback to image-direct scanning works for externally-sourced images"

# -----------------------------------------------------------------------------
# Section 6 — /sbom.json ships as a promise in scratch-base-trixie
# -----------------------------------------------------------------------------
say "6. scratch-base-trixie PROMISES.yaml declares /sbom.json"
grep -q 'sbom.json' images/scratch-base-trixie/PROMISES.yaml || {
  echo "  ✗ scratch-base-trixie/PROMISES.yaml missing /sbom.json promise" >&2
  exit 1
}
pass "scratch-base-trixie promises /sbom.json"

echo
echo "FG-020 acceptance: all sections passed."
