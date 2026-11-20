#!/usr/bin/env bash
# Smoke — python-scratch-trixie ships compiled C.UTF-8 + en_US.UTF-8
# locales and `locale.setlocale(...)` succeeds for both; strcoll
# distinguishes them (en_US.UTF-8 = Unicode alphabetical,
# C.UTF-8 = byte order).
#
# Delivers: FG-033 Scenarios "Both locales ship in python-scratch-trixie",
# "Python setlocale succeeds for both locales", "Python strcoll
# distinguishes the two locales".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-python-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-3.14}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# -----------------------------------------------------------------------------
# 1. Content check — both locale dirs present in the image
# -----------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
docker save "${IMAGE}" -o "${TMP}/image.tar"
tar -xf "${TMP}/image.tar" -C "${TMP}" manifest.json
mapfile -t layers < <(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
for L in m[0]["Layers"]:
    print(L)
' "${TMP}/manifest.json")

found_c=0; found_en=0
for layer in "${layers[@]}"; do
  tar -xf "${TMP}/image.tar" -C "${TMP}" "${layer}"
  # grep -c + || true so pipefail + set -e don't interfere with "no match → 0"
  c_count=$(tar -tf "${TMP}/${layer}" 2>/dev/null \
            | grep -cE '(^|/)usr/lib/locale/C\.utf8/LC_CTYPE$' || true)
  en_count=$(tar -tf "${TMP}/${layer}" 2>/dev/null \
             | grep -cE '(^|/)usr/lib/locale/en_US\.utf8/LC_CTYPE$' || true)
  [[ "${c_count}"  -ge 1 ]] && found_c=1
  [[ "${en_count}" -ge 1 ]] && found_en=1
done
[[ "${found_c}"  -eq 1 ]] || { echo "  ✗ /usr/lib/locale/C.utf8/LC_CTYPE missing"  >&2; exit 1; }
[[ "${found_en}" -eq 1 ]] || { echo "  ✗ /usr/lib/locale/en_US.utf8/LC_CTYPE missing" >&2; exit 1; }
echo "  ✓ /usr/lib/locale/{C.utf8,en_US.utf8}/LC_CTYPE both present"

# -----------------------------------------------------------------------------
# 2. setlocale succeeds for both locales
# -----------------------------------------------------------------------------
set +e
out=$(docker run --rm "${IMAGE}" -c "import locale; print(locale.setlocale(locale.LC_ALL, 'C.UTF-8'))" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 || "${out}" != "C.UTF-8" ]]; then
  echo "  ✗ setlocale(LC_ALL, 'C.UTF-8') failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ setlocale(LC_ALL, 'C.UTF-8') = 'C.UTF-8'"

set +e
out=$(docker run --rm "${IMAGE}" -c "import locale; print(locale.setlocale(locale.LC_ALL, 'en_US.UTF-8'))" 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 || "${out}" != "en_US.UTF-8" ]]; then
  echo "  ✗ setlocale(LC_ALL, 'en_US.UTF-8') failed (rc=${rc}): ${out}" >&2
  exit 1
fi
echo "  ✓ setlocale(LC_ALL, 'en_US.UTF-8') = 'en_US.UTF-8'"

# -----------------------------------------------------------------------------
# 3. strcoll distinguishes the two locales
#    - en_US.UTF-8: Unicode-alphabetical  → strcoll('ä', 'z') < 0
#    - C.UTF-8:     byte order            → strcoll('ä', 'z') > 0
# -----------------------------------------------------------------------------
probe='
import locale, sys
loc = sys.argv[1]
locale.setlocale(locale.LC_ALL, loc)
cmp = locale.strcoll("ä", "z")
sign = "neg" if cmp < 0 else ("pos" if cmp > 0 else "zero")
print(sign)
'

got=$(docker run --rm "${IMAGE}" -c "${probe}" en_US.UTF-8 2>&1)
[[ "${got}" == "neg" ]] || {
  echo "  ✗ en_US.UTF-8 strcoll('ä', 'z') sign = '${got}', expected 'neg'" >&2
  exit 1
}
echo "  ✓ en_US.UTF-8 strcoll('ä', 'z') < 0  (Unicode alphabetical)"

got=$(docker run --rm "${IMAGE}" -c "${probe}" C.UTF-8 2>&1)
[[ "${got}" == "pos" ]] || {
  echo "  ✗ C.UTF-8 strcoll('ä', 'z') sign = '${got}', expected 'pos'" >&2
  exit 1
}
echo "  ✓ C.UTF-8 strcoll('ä', 'z') > 0  (byte order)"
