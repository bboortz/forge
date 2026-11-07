#!/usr/bin/env python3
# FG-017 — Emit the set of image dirs affected by the diff between BASE and HEAD.
#
# Direct affect: any file under images/<name>/* was touched by the diff.
# Transitive affect: an image's PROMISES.yaml had a promise REMOVED or
#     MODIFIED-same-id; every dependent (per its EXPECTATIONS.yaml) is
#     also affected. Pure ADD of a new promise is semver-safe (no fan-out).
#
# Output: one image dir name per line to stdout. Exit 0 always on success.
#
# Usage:
#   scripts/affected_images.py <BASE_REF>
#     e.g. scripts/affected_images.py origin/dev
#
# Reuses the YAML loader + graph shape from verify-contracts.py, but without
# importing it (keeping that script self-contained for its own gate role).

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "affected_images: python3-yaml missing. Install via your package "
        "manager (apt install python3-yaml / pip install pyyaml).\n"
    )
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"


def git_diff_names(base: str) -> list[str]:
    try:
        p = subprocess.run(
            ["git", "diff", "--name-only", f"{base}..HEAD"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        )
    except subprocess.CalledProcessError:
        return []
    return [line for line in p.stdout.splitlines() if line.strip()]


def git_show(ref: str, path: str) -> str | None:
    p = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if p.returncode != 0:
        return None
    return p.stdout


def load_promises_from_ref(ref: str, image: str) -> dict[str, str] | None:
    """id → description map. None if the file doesn't exist at that ref."""
    text = git_show(ref, f"images/{image}/PROMISES.yaml")
    if text is None:
        return None
    try:
        data = yaml.safe_load(text) or {}
    except yaml.YAMLError:
        return None
    out = {}
    for p in data.get("promises", []) or []:
        pid = p.get("id")
        if isinstance(pid, str):
            out[pid] = p.get("description", "")
    return out


def load_expectations_graph() -> dict[str, set[str]]:
    """image → set of dependency image dir names. Based on current HEAD state."""
    graph: dict[str, set[str]] = {}
    for p in IMAGES_DIR.glob("*/EXPECTATIONS.yaml"):
        try:
            data = yaml.safe_load(p.read_text()) or {}
        except yaml.YAMLError:
            continue
        img = p.parent.name
        deps = {
            dep.get("image")
            for dep in (data.get("dependencies") or [])
            if isinstance(dep, dict) and isinstance(dep.get("image"), str)
        }
        graph[img] = {d for d in deps if d}
    return graph


def dependents_of(graph: dict[str, set[str]], image: str) -> set[str]:
    """Images that depend on `image` (direct + transitive)."""
    out: set[str] = set()
    stack = [image]
    while stack:
        cur = stack.pop()
        for candidate, deps in graph.items():
            if cur in deps and candidate not in out:
                out.add(candidate)
                stack.append(candidate)
    return out


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: affected_images.py <BASE_REF>\n")
        return 2
    base = sys.argv[1]

    changed = git_diff_names(base)
    if not changed:
        return 0

    # Direct: any image whose files changed
    direct: set[str] = set()
    all_images = {p.name for p in IMAGES_DIR.iterdir() if p.is_dir()}
    for line in changed:
        parts = line.split("/", 2)
        if len(parts) >= 2 and parts[0] == "images" and parts[1] in all_images:
            direct.add(parts[1])

    affected = set(direct)

    # Transitive: PROMISES promise removed / modified → fan-out to dependents
    graph = load_expectations_graph()
    for img in direct:
        old = load_promises_from_ref(base, img)
        new = load_promises_from_ref("HEAD", img)
        if old is None or new is None:
            continue
        removed = set(old) - set(new)
        modified = {k for k in set(old) & set(new) if old[k] != new[k]}
        if removed or modified:
            for dependent in dependents_of(graph, img):
                affected.add(dependent)

    for name in sorted(affected):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
