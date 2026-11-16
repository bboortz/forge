#!/usr/bin/env python3
# FG-059 — Emit the reverse-dependency graph derived from `images/*/Dockerfile`.
#
# For every Dockerfile in images/*/:
#   - `^ARG <NAME>_REF=ghcr.io/bboortz/<forge-image>[:@]...`  →  dep on <forge-image>
#   - `^FROM ghcr.io/bboortz/<forge-image>[:@]...`           →  dep on <forge-image>
#
# Only edges where the referenced image exists under images/<forge-image>/
# are kept (ignores stale external references or Docker Hub refs).
#
# Output shape (JSON, stdout):
#   { "<image>": ["<images-that-FROM-it>", ...],  ... }
#
# Keys are the depended-upon image; values are the reverse set of dependents
# (fan-out orientation — when <image> changes, every listed dependent is
# transitively affected).
#
# Usage:
#   scripts/image_from_graph.py            # full JSON to stdout
#   scripts/image_from_graph.py --deps <image>  # one-line deps for <image> only

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"

# Match `ARG NAME_REF=ghcr.io/bboortz/<forge-image>[:@]...`
# or   `FROM ghcr.io/bboortz/<forge-image>[:@]...`  (possibly with a comment after)
# Allow leading whitespace (defensive, though Dockerfile ARGs typically start at col 0).
_ARG_RE  = re.compile(r"^\s*ARG\s+[A-Z_]+_REF\s*=\s*ghcr\.io/bboortz/([a-z0-9][a-z0-9-]*)[:@]")
_FROM_RE = re.compile(r"^\s*FROM\s+ghcr\.io/bboortz/([a-z0-9][a-z0-9-]*)[:@]")


def all_images() -> set[str]:
    return {p.name for p in IMAGES_DIR.iterdir() if p.is_dir() and (p / "image.yaml").is_file()}


def parse_dockerfile_deps(dockerfile: Path, known: set[str]) -> set[str]:
    """Return the set of forge-images this Dockerfile declares as a dep."""
    deps: set[str] = set()
    try:
        content = dockerfile.read_text()
    except OSError:
        return deps
    for line in content.splitlines():
        # Strip inline comments but keep leading whitespace for the anchor
        # detection in the regex. Lines starting with `#` after optional
        # leading whitespace don't match (pattern requires ARG/FROM keyword).
        stripped = line.split("#", 1)[0].rstrip()
        if not stripped:
            continue
        m = _ARG_RE.match(stripped) or _FROM_RE.match(stripped)
        if not m:
            continue
        candidate = m.group(1)
        if candidate in known:
            deps.add(candidate)
    return deps


def build_forward_graph() -> dict[str, set[str]]:
    """Forward graph: image → {images it depends on}."""
    images = all_images()
    graph: dict[str, set[str]] = {img: set() for img in images}
    for img in images:
        dockerfile = IMAGES_DIR / img / "Dockerfile"
        if not dockerfile.is_file():
            continue
        deps = parse_dockerfile_deps(dockerfile, images)
        # Self-loop guard: a Dockerfile shouldn't FROM itself. Treat as no edge.
        deps.discard(img)
        graph[img] = deps
    return graph


def reverse_graph(forward: dict[str, set[str]]) -> dict[str, set[str]]:
    """{base image → {dependents that FROM it}}."""
    reverse: dict[str, set[str]] = {img: set() for img in forward}
    for src, targets in forward.items():
        for t in targets:
            reverse.setdefault(t, set()).add(src)
    return reverse


def detect_cycles(forward: dict[str, set[str]]) -> list[list[str]]:
    """DFS-based cycle detector. Returns list of cycles found (each as a node sequence).

    Dockerfile FROMs cannot be cyclic in practice (base must exist first), but
    a bug in the parser could create one — fail loudly rather than loop.
    """
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in forward}
    cycles: list[list[str]] = []
    stack: list[str] = []

    def visit(n: str) -> None:
        color[n] = GRAY
        stack.append(n)
        for m in sorted(forward.get(n, ())):
            if color.get(m, WHITE) == GRAY:
                # Back-edge: extract the cycle
                try:
                    i = stack.index(m)
                    cycles.append(stack[i:] + [m])
                except ValueError:
                    cycles.append([n, m])
            elif color.get(m, WHITE) == WHITE:
                visit(m)
        stack.pop()
        color[n] = BLACK

    for n in sorted(forward):
        if color[n] == WHITE:
            visit(n)
    return cycles


def main() -> int:
    forward = build_forward_graph()

    cycles = detect_cycles(forward)
    if cycles:
        sys.stderr.write("image_from_graph: cycle(s) detected in Dockerfile FROM graph:\n")
        for c in cycles:
            sys.stderr.write("  " + " -> ".join(c) + "\n")
        return 2

    reverse = reverse_graph(forward)

    if len(sys.argv) == 3 and sys.argv[1] == "--deps":
        # Print one dep per line for a single image (easier for shell callers).
        target = sys.argv[2]
        for dep in sorted(reverse.get(target, ())):
            print(dep)
        return 0

    out = {k: sorted(v) for k, v in sorted(reverse.items()) if v}
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
