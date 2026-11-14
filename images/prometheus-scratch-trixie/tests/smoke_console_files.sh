#!/usr/bin/env bash
# Smoke — /usr/share/prometheus/consoles + /usr/share/prometheus/console_libraries
# files are present in the image. Homelab (and operators following the
# Prometheus manual) pass --web.console.templates=/usr/share/prometheus/
# consoles and --web.console.libraries=/usr/share/prometheus/console_libraries
# as absolute paths. The server needs those dirs to exist + contain the
# standard upstream template set (index.html.example, node.html, prometheus.html,
# etc.) + libraries (menu.lib, prom.lib).
#
# Catches a regression where from-source migration forgets to copy the
# consoles/console_libraries trees from the git checkout into /out.
#
# Delivers: FG-048 homelab-compat scenario "console templates ship".

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-prometheus-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2.53}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Use docker save + tar to inspect scratch filesystem (no shell to ls with).
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

docker save "${IMAGE}" -o "${TMP}/i.tar"
tar -xf "${TMP}/i.tar" -C "${TMP}" manifest.json

# Walk LAYER order (manifest.json .Layers[] — alphabetical sort is wrong for
# scratch-overlay images, see memory/scratch-closures.md).
mapfile -t layers < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for L in m[0]["Layers"]:
    print(L)
' "${TMP}/manifest.json")

declare -A found
for L in "${layers[@]}"; do
  tar -xf "${TMP}/i.tar" -C "${TMP}" "${L}"
  while read -r path; do
    found["${path}"]=1
  done < <(tar -tf "${TMP}/${L}" 2>/dev/null \
            | grep -E '(^|/)usr/share/prometheus/(consoles|console_libraries)/' || true)
done

# At minimum we expect the directories to exist. The exact file set depends
# on upstream prometheus version — we don't hardcode specific filenames.
have_consoles=0
have_libs=0
for k in "${!found[@]}"; do
  [[ "${k}" == *usr/share/prometheus/consoles/* ]] && have_consoles=1
  [[ "${k}" == *usr/share/prometheus/console_libraries/* ]] && have_libs=1
done

if [[ "${have_consoles}" -eq 0 ]]; then
  echo "  ✗ /usr/share/prometheus/consoles/ is empty or missing in image" >&2
  echo "    (homelab compose passes --web.console.templates pointing here;" >&2
  echo "     from-source build must cp -r consoles /out/usr/share/prometheus/)" >&2
  exit 1
fi
if [[ "${have_libs}" -eq 0 ]]; then
  echo "  ✗ /usr/share/prometheus/console_libraries/ is empty or missing" >&2
  echo "    (homelab compose passes --web.console.libraries pointing here)" >&2
  exit 1
fi
echo "  ✓ /usr/share/prometheus/consoles + console_libraries present (homelab-compat)"
