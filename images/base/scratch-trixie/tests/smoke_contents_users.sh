#!/usr/bin/env bash
# Baseline identity contract (FG-008): /etc/passwd + /etc/group must
# contain root (0), nonroot (65532, distroless convention), nobody (65534).
#
# Tested via docker save + tar inspection since baseline has no exec.
#
# Delivers: FG-008 Scenario "baseline provides standard reserved UIDs".
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-scratch-base-trixie}"
IMAGE_TAG="${IMAGE_TAG:-0.2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT
docker save "${IMAGE}" -o "${tmp}/img.tar"
tar xf "${tmp}/img.tar" -C "${tmp}"

# Walk layers in manifest.json order (bottom-up) so later overlays win —
# baseline has one content layer today but keep the pattern consistent
# with FG-007's uid-pin check.
while IFS= read -r layer; do
  tar xf "${tmp}/${layer}" -C "${tmp}" etc/passwd etc/group 2>/dev/null || true
done < <(jq -r '.[0].Layers[]' "${tmp}/manifest.json")

required_passwd=(
  "^root:x:0:0:"
  "^nonroot:x:65532:65532:nonroot:/nonroot:"
  "^nobody:x:65534:65534:"
)
required_group=(
  "^root:x:0:"
  "^nonroot:x:65532:"
  "^nobody:x:65534:"
)

for re in "${required_passwd[@]}"; do
  if ! grep -qE "${re}" "${tmp}/etc/passwd"; then
    echo "  ✗ /etc/passwd missing line matching: ${re}" >&2
    echo "--- /etc/passwd ---" >&2
    cat "${tmp}/etc/passwd" >&2
    exit 1
  fi
done
for re in "${required_group[@]}"; do
  if ! grep -qE "${re}" "${tmp}/etc/group"; then
    echo "  ✗ /etc/group missing line matching: ${re}" >&2
    cat "${tmp}/etc/group" >&2
    exit 1
  fi
done

echo "  ✓ /etc/passwd + /etc/group have root (0), nonroot (65532), nobody (65534)"
