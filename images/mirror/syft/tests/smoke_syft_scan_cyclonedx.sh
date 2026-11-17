#!/usr/bin/env bash
# Smoke — mirror/syft produces parseable CycloneDX JSON for a small OCI image.
# Uses the just-built mirror/syft image itself as the scan target (it's local;
# no additional pull required).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mirror/syft}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Point syft at a tiny scratch-based target. We use mirror/syft scanning
# mirror/syft — catalogers run but find minimal packages.
set +e
out=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        "${IMAGE}" scan "${IMAGE}" -o cyclonedx-json 2>&1)
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ syft scan exited ${rc}:" >&2
  echo "${out}" | tail -20 >&2
  exit 1
fi
# Parseable JSON with a bomFormat field (CycloneDX convention).
if ! echo "${out}" | jq -e '.bomFormat == "CycloneDX"' >/dev/null; then
  echo "  ✗ syft output is not a CycloneDX JSON document:" >&2
  echo "${out}" | head -5 >&2
  exit 1
fi
echo "  ✓ syft produces CycloneDX JSON (bomFormat=CycloneDX)"
