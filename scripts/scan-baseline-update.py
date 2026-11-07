#!/usr/bin/env python3
# FG-019 — Regenerate images/<name>/scan-baseline.json from the current
# local build's grype scan.
#
# Devs run this when intentionally accepting a baseline change (e.g.,
# upstream can't patch a CRITICAL in the near term and the waiver isn't
# the right answer; or on first publish of a new image).
#
# Usage:
#   make scan-baseline-update IMAGE_DIR=<image-dir>
#   scripts/scan-baseline-update.py <image-dir>

from __future__ import annotations

import sys
from pathlib import Path

# Re-use the loader + extractor from scan-regression.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

# Dynamic import so pyimport of a dashed-name module works.
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "scan_regression", REPO_ROOT / "scripts" / "scan-regression.py"
)
if _spec is None or _spec.loader is None:
    sys.stderr.write("scan-baseline-update: couldn't load scripts/scan-regression.py\n")
    sys.exit(2)
sr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sr)

IMAGES_DIR = REPO_ROOT / "images"


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: scan-baseline-update.py <image-dir>\n")
        return 2
    image_name = sys.argv[1]
    image_dir = IMAGES_DIR / image_name
    if not image_dir.is_dir():
        sys.stderr.write(f"no such image dir: {image_dir}\n")
        return 2

    image_ref = sr.resolve_image_ref(image_dir)
    print(f"→ scan-baseline-update {image_name} ({image_ref})")

    # FG-020: prefer the embedded SBOM when available (dpkg-aware Debian matcher)
    sbom_path = sr.extract_sbom(image_ref)
    if sbom_path is not None:
        print(f"  using embedded SBOM: {sbom_path}")
    scan = sr.run_grype(image_ref, sbom_path)
    current = sr.extract_critical_cves(scan)

    bpath = image_dir / "scan-baseline.json"
    sr.write_baseline(bpath, current)
    print(f"  wrote {bpath.relative_to(REPO_ROOT)}: {len(current)} CRITICAL CVE(s) "
          f"{'(zero — clean image)' if not current else f'{sorted(current)}'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
