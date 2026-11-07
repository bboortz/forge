#!/usr/bin/env python3
# FG-019 — Per-image scan-regression gate.
#
# Builds a current grype scan, extracts CRITICAL CVE IDs, diffs vs the
# committed baseline (images/<name>/scan-baseline.json), subtracts any
# waivers declared in PROMISES.yaml (absence.os-cves.waivers), and fails
# if any net-new CRITICAL remains.
#
# Usage:
#   scripts/scan-regression.py <image-dir>
#     e.g. scripts/scan-regression.py beaconry-scout
#
# Exit codes:
#   0 — no new CRITICAL (or auto-bootstrapped a missing baseline)
#   1 — new CRITICAL CVE(s) detected
#   2 — environmental problem (grype missing, image.yaml unreadable)

from __future__ import annotations

import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("scan-regression: python3-yaml missing. Install via your package manager.\n")
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"
BASELINE_SCHEMA_VERSION = 1


def say(msg: str) -> None:
    print(f"→ {msg}")


def warn(msg: str) -> None:
    sys.stderr.write(f"⚠ {msg}\n")


def err(msg: str) -> None:
    sys.stderr.write(f"✗ {msg}\n")


def read_yaml(path: Path) -> dict:
    try:
        return yaml.safe_load(path.read_text()) or {}
    except (yaml.YAMLError, OSError):
        return {}


def resolve_image_ref(image_dir: Path) -> str:
    """Extract REGISTRY/repo:tag from image.yaml. REGISTRY defaults forge-local."""
    iy = image_dir / "image.yaml"
    data = read_yaml(iy)
    tag = str(data.get("tag") or "")
    if not tag:
        err(f"{iy}: missing 'tag:' field")
        sys.exit(2)
    repo = str(data.get("repo") or image_dir.name)
    registry = os.environ.get("REGISTRY", "forge-local")
    return f"{registry}/{repo}:{tag}"


def run_grype(image_ref: str) -> dict:
    """Runs grype against the given image and returns parsed JSON."""
    if not subprocess.run(["which", "grype"], capture_output=True).returncode == 0:
        err("grype not installed (install via: make tools)")
        sys.exit(2)
    try:
        p = subprocess.run(
            ["grype", image_ref, "-o", "json"],
            capture_output=True, text=True, check=True, timeout=120,
        )
    except subprocess.CalledProcessError as e:
        # grype may exit non-zero with --fail-on; here we didn't pass --fail-on,
        # so a non-zero exit is a real tool error.
        err(f"grype exited {e.returncode}: {e.stderr[:200]}")
        sys.exit(2)
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        err(f"grype output isn't valid JSON: {e}")
        sys.exit(2)


def extract_critical_cves(scan: dict) -> set[str]:
    """Set of CVE IDs where severity is Critical."""
    out: set[str] = set()
    for match in (scan.get("matches") or []):
        vuln = match.get("vulnerability") or {}
        sev = str(vuln.get("severity") or "").lower()
        cve_id = str(vuln.get("id") or "")
        if sev == "critical" and cve_id:
            out.add(cve_id)
    return out


def load_baseline(image_dir: Path) -> tuple[set[str] | None, Path]:
    """Returns (baseline_cve_set, path). baseline_cve_set is None if the file
    doesn't exist (triggers auto-bootstrap)."""
    bpath = image_dir / "scan-baseline.json"
    if not bpath.exists():
        return None, bpath
    try:
        data = json.loads(bpath.read_text())
    except (OSError, json.JSONDecodeError) as e:
        err(f"{bpath}: invalid JSON — {e}")
        sys.exit(2)
    if int(data.get("version", 0)) != BASELINE_SCHEMA_VERSION:
        err(f"{bpath}: unsupported schema version (want {BASELINE_SCHEMA_VERSION})")
        sys.exit(2)
    return set(data.get("critical_cves") or []), bpath


def load_waivers(image_dir: Path) -> set[str]:
    """Set of CVE IDs waivered by this image's PROMISES.yaml absence.os-cves entry.
    Expired waivers are silently filtered OUT (fail-closed); verify-contracts
    is responsible for rejecting them before we get here."""
    pp = image_dir / "PROMISES.yaml"
    if not pp.exists():
        return set()
    data = read_yaml(pp)
    waivers: set[str] = set()
    today = datetime.date.today()
    for promise in (data.get("promises") or []):
        if promise.get("id") != "absence.os-cves":
            continue
        for w in (promise.get("waivers") or []):
            cve = w.get("cve")
            until = w.get("until")
            if not isinstance(cve, str) or not isinstance(until, str):
                continue
            try:
                until_date = datetime.date.fromisoformat(until)
            except ValueError:
                continue
            if until_date < today:
                continue  # expired — don't apply
            waivers.add(cve)
    return waivers


def write_baseline(path: Path, cves: set[str]) -> None:
    """Write a new baseline file (auto-bootstrap path)."""
    data = {
        "version": BASELINE_SCHEMA_VERSION,
        "critical_cves": sorted(cves),
        "generated_at": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "note": "regenerate with: make scan-baseline-update IMAGE_DIR=<dir>",
    }
    path.write_text(json.dumps(data, indent=2) + "\n")


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: scan-regression.py <image-dir>\n")
        return 2
    image_name = sys.argv[1]
    image_dir = IMAGES_DIR / image_name
    if not image_dir.is_dir():
        err(f"no such image dir: {image_dir}")
        return 2

    image_ref = resolve_image_ref(image_dir)
    say(f"scan-regression {image_name} ({image_ref})")

    scan = run_grype(image_ref)
    current = extract_critical_cves(scan)

    baseline, bpath = load_baseline(image_dir)
    waivers = load_waivers(image_dir)

    if baseline is None:
        # Q4=a auto-bootstrap: write baseline from current scan + warn.
        write_baseline(bpath, current)
        warn(f"{bpath.relative_to(REPO_ROOT)} didn't exist — auto-bootstrapped with "
             f"{len(current)} CRITICAL CVE(s). Commit this file.")
        return 0

    new_critical = current - baseline - waivers
    if new_critical:
        err(f"scan-regression FAIL: {len(new_critical)} new CRITICAL CVE(s) in {image_name}:")
        for cve in sorted(new_critical):
            # Find the matching artifact(s) for actionable output.
            artifacts: list[str] = []
            for match in (scan.get("matches") or []):
                v = match.get("vulnerability") or {}
                if str(v.get("id")) == cve:
                    a = match.get("artifact") or {}
                    artifacts.append(f"{a.get('name', '?')}@{a.get('version', '?')}")
            art_str = ", ".join(sorted(set(artifacts))) or "(no artifact info)"
            sys.stderr.write(f"    - {cve}  [{art_str}]\n")
        sys.stderr.write(
            f"\n  To accept: either (a) fix/upgrade the package, (b) add a waiver to\n"
            f"  images/{image_name}/PROMISES.yaml absence.os-cves.waivers with a reason +\n"
            f"  until date, or (c) `make scan-baseline-update IMAGE_DIR={image_name}` to\n"
            f"  accept into baseline (semver-bump PROMISES.yaml if this was unexpected).\n"
        )
        return 1

    # Soft note on waivered/baselined counts
    print(f"scan-regression: ok  baseline={len(baseline)}  waivered={len(waivers)}  current={len(current)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
