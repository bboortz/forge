#!/usr/bin/env python3
# FG-059 — Emit the reverse-dependency graph derived from images/*/Dockerfile.
# FG-064 — Add mermaid emitter for docs/image-dependency-graph.md (drift-gated).
#
# For every Dockerfile in images/*/:
#   - `^ARG <NAME>_REF=ghcr.io/bboortz/<forge-image>[:@]...`  →  dep on <forge-image>
#   - `^FROM ghcr.io/bboortz/<forge-image>[:@]...`           →  dep on <forge-image>
#
# FG-064 adds:
#   - Literal `^FROM <upstream>:<tag>` extraction (upstream Docker Hub anchors)
#   - ARG-indirect FROMs: `FROM ${X}` resolves via ARG default
#   - `COPY --from=<stage>` edge extraction (hc + scratch-base overlays)
#   - Role classification + 5-layer mermaid subgraph emission
#   - External-sourced images (image.yaml has `source:`) → fallback to
#     image.yaml depends_on since the Dockerfile lives in a remote repo.
#
# Usage:
#   scripts/image_from_graph.py                  # reverse-JSON (FG-059 default)
#   scripts/image_from_graph.py --deps <image>   # one-line deps for <image>
#   scripts/image_from_graph.py --emit=mermaid   # FG-064 mermaid block
#   scripts/image_from_graph.py --emit=mermaid --write docs/image-dependency-graph.md
#                                                # rewrite between GENERATED markers

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None  # type: ignore

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"

# FG-068: import the L0.1 upstream-source inventory so the dep graph can
# emit source nodes + edges to their declared consumers.
sys.path.insert(0, str(REPO_ROOT / "scripts"))
try:
    from _upstream_sources import _UPSTREAM_SOURCES  # type: ignore
except ImportError:  # inventory not present — degrade gracefully
    _UPSTREAM_SOURCES = {}  # type: ignore

# Role classification — mirrors scripts/discover-images.sh.
_PRE_BUILDERS = [
    "pre-builder/debian-slim-sid",
    "pre-builder/debian-slim-trixie",
    "pre-builder/go-slim-trixie",
    "pre-builder/node-slim-trixie",
    "pre-builder/python-slim-trixie",
    "pre-builder/ubuntu-slim-noble",
    "pre-builder/zig-slim-trixie",
    "pre-builder/alpine-3",        # FG-079
]
_FORGE_BUILDERS = [
    "builder/go-trixie",
    "builder/node-trixie",
    "builder/python-trixie",
    "builder/zig-trixie",
]
_BASELINE = [
    "base/scratch-trixie",
    "base/python-scratch-trixie",
    "base/python-slim-trixie",
    "base/debian-slim-trixie",   # FG-077
    "base/ubuntu-slim-noble",    # FG-077
    "base/node-slim-trixie",     # FG-077
    "base/alpine-3",             # FG-079
    "base/scratch-alpine-3",     # FG-080
]
_UPSTREAM_HELPERS = ["hc"]  # ghcr.io/bboortz/hc — forge-published but external to the layered fleet
# FG-066: forge mirror tier — zero-mod passthroughs under images/mirror/<name>/.
_FORGE_MIRRORS = ["mirror/syft"]

_UPSTREAM_ANCHORS = {
    "debian:trixie-slim",
    "debian:sid-slim",
    "python:3.14-slim-trixie",
    "ubuntu:24.04",
    "node:24-trixie-slim",
    "golang:1.27-trixie",
    "postgres:18",
    "alpine:3",                  # FG-079
}
_HELPER_UPSTREAMS = {
    "docker.io/anchore/syft:latest",
    "anchore/syft:latest",
}

# Mermaid node ids for upstream nodes (image dir names reused for local images).
_UPSTREAM_NODE_IDS = {
    "debian:trixie-slim":      ("UP_DEBIAN_TRIXIE",   "debian:trixie-slim<br/>docker.io"),
    "debian:sid-slim":         ("UP_DEBIAN_SID",      "debian:sid-slim<br/>docker.io"),
    "python:3.14-slim-trixie": ("UP_PYTHON",          "python:3.14-slim-trixie<br/>docker.io"),
    "ubuntu:24.04":            ("UP_UBUNTU",          "ubuntu:24.04<br/>docker.io"),
    "node:24-trixie-slim":     ("UP_NODE",            "node:24-trixie-slim<br/>docker.io"),
    "golang:1.27-trixie":      ("UP_GOLANG",          "golang:1.27-trixie<br/>docker.io"),
    "postgres:18":             ("UP_POSTGRES",        "postgres:18<br/>docker.io"),
    "alpine:3":                ("UP_ALPINE",          "alpine:3<br/>docker.io"),
    "docker.io/anchore/syft:latest": ("UP_SYFT",      "anchore/syft:latest<br/>docker.io"),
    "anchore/syft:latest":           ("UP_SYFT",      "anchore/syft:latest<br/>docker.io"),
    "hc":                       ("UP_HC",             "hc:0.1.0<br/>ghcr.io/bboortz<br/>(static Zig healthcheck)"),
    "BEACONRY_SRC":             ("UP_BEACONRY",       "beaconry (source)<br/>github.com/bboortz/beaconry"),
}

_ARG_REF_RE = re.compile(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\S+)")
_FROM_RE = re.compile(r"^\s*FROM\s+(\S+)(?:\s+AS\s+(\S+))?\s*$")
_COPY_FROM_RE = re.compile(r"^\s*COPY\s+--from=([A-Za-z0-9_][A-Za-z0-9_-]*)\b")
_ARG_SUBST_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")
# FG-066: allow nested paths (`mirror/<name>`) in ghcr.io / forge-local refs.
_GHCR_REF_RE = re.compile(r"^ghcr\.io/bboortz/([a-z0-9][a-z0-9-]*(?:/[a-z0-9][a-z0-9-]*)?):[a-zA-Z0-9._-]+$")
_FORGE_LOCAL_REF_RE = re.compile(r"^forge-local/([a-z0-9][a-z0-9-]*(?:/[a-z0-9][a-z0-9-]*)?):[a-zA-Z0-9._-]+$")


def all_images() -> set[str]:
    # FG-066: walk 2 levels deep so nested `images/mirror/<name>/` dirs
    # surface as `mirror/<name>` canonically.
    out: set[str] = set()
    for p in IMAGES_DIR.iterdir():
        if not p.is_dir():
            continue
        if (p / "image.yaml").is_file():
            out.add(p.name)
            continue
        for sub in p.iterdir():
            if sub.is_dir() and (sub / "image.yaml").is_file():
                out.add(f"{p.name}/{sub.name}")
    return out


_STAGE_HAS_CONTENT_CMDS = re.compile(r"^\s*(RUN|CMD|ENTRYPOINT|ADD|COPY|WORKDIR|USER|ENV|LABEL|EXPOSE|VOLUME|HEALTHCHECK|SHELL|STOPSIGNAL)\b")


def _parse_dockerfile(df: Path) -> tuple[dict[str, str | None], list[tuple[str, str | None, bool]], list[str]]:
    """Return (arg_defaults, from_entries, copy_from_stages).

    arg_defaults: {ARG_NAME: default-string-or-None}
    from_entries: list of (target, stage, has_content). has_content is True
        if the stage has any RUN/CMD/etc. between its FROM and the next FROM
        (OR it's the last FROM in the file — the runtime stage, which is
        always considered "has_content" even for a bare FROM scratch).
    copy_from_stages: list of stage names referenced by COPY --from=
    """
    arg_defaults: dict[str, str | None] = {}
    raw_froms: list[tuple[int, str, str | None]] = []  # (lineno, target, stage)
    copy_stages: list[str] = []
    lines: list[str] = []

    try:
        content = df.read_text()
    except OSError:
        return arg_defaults, [], copy_stages

    for i, raw in enumerate(content.splitlines(), start=1):
        line = raw.split("#", 1)[0].rstrip()
        lines.append(line)
        if not line:
            continue
        if m := _ARG_REF_RE.match(line):
            arg_defaults[m.group(1)] = m.group(2)
            continue
        if m := re.match(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", line):
            arg_defaults[m.group(1)] = None
            continue
        if m := _FROM_RE.match(line):
            raw_froms.append((i, m.group(1), m.group(2)))
            continue
        if m := _COPY_FROM_RE.match(line):
            copy_stages.append(m.group(1))

    # Determine has_content per stage. Last stage is always has_content=True
    # (it's the runtime). Earlier stages are has_content=True iff any
    # content-directive appears between this FROM's line and the next FROM.
    froms: list[tuple[str, str | None, bool]] = []
    for idx, (lineno, target, stage) in enumerate(raw_froms):
        is_last = (idx == len(raw_froms) - 1)
        next_lineno = raw_froms[idx + 1][0] if not is_last else len(lines) + 1
        has_content = is_last  # runtime stage always counts
        for j in range(lineno, next_lineno - 1):
            if _STAGE_HAS_CONTENT_CMDS.match(lines[j]):
                has_content = True
                break
        froms.append((target, stage, has_content))

    return arg_defaults, froms, copy_stages


def _resolve_target(target: str, arg_defaults: dict[str, str | None], local_images: set[str]) -> tuple[str, str] | None:
    """Resolve a FROM target to (kind, resolved-name).

    kind: 'local' (resolved is an image dir), 'upstream' (resolved is the upstream tag),
          'helper' (upstream helper like syft), 'scratch' (resolved is 'scratch'),
          'unknown' otherwise.
    """
    if target == "scratch":
        return ("scratch", "scratch")
    if m := _ARG_SUBST_RE.match(target):
        arg_name = m.group(1)
        default = arg_defaults.get(arg_name)
        if not default:
            return None
        return _resolve_target(default, arg_defaults, local_images)
    if m := _GHCR_REF_RE.match(target):
        tgt = m.group(1)
        if tgt in local_images:
            return ("local", tgt)
        if tgt in _UPSTREAM_HELPERS:
            return ("helper-local", tgt)
        return None
    if m := _FORGE_LOCAL_REF_RE.match(target):
        tgt = m.group(1)
        if tgt in local_images:
            return ("local", tgt)
        return None
    if target in _UPSTREAM_ANCHORS:
        return ("upstream", target)
    if target in _HELPER_UPSTREAMS:
        return ("helper-upstream", target)
    return None


def _load_image_yaml(image: str) -> dict:
    if yaml is None:
        return {}
    p = IMAGES_DIR / image / "image.yaml"
    if not p.is_file():
        return {}
    try:
        return yaml.safe_load(p.read_text()) or {}
    except Exception:
        return {}


def build_full_graph(local_images: set[str]):
    """Return (forward, dashed_local, upstream_solid, upstream_dashed, external, final_src).

    forward[image] = {local images this image FROMs with content (builder/runtime)}
    dashed_local = list of (source-local, image) tuples where source is used ONLY
        as a COPY --from= target (no content-directives in the stage)
    upstream_solid = list of (upstream-ref, image) — FROM with content
    upstream_dashed = list of (upstream-ref, image) — stage used only as COPY --from=
    external = set of image dir names with image.yaml source: block
    final_src[image] = (kind, name) of the final-stage FROM resolution (post-FG-076:
        used to distinguish Class 1 FROM-parent from Class 2 FROM-builder-stage).
        None for scratch final-stage or unresolvable final FROM.
    """
    forward: dict[str, set[str]] = {img: set() for img in local_images}
    dashed_local: list[tuple[str, str]] = []
    upstream_solid: list[tuple[str, str]] = []
    upstream_dashed: list[tuple[str, str]] = []
    external: set[str] = set()
    final_src: dict[str, tuple[str, str] | None] = {}

    for img in sorted(local_images):
        yml = _load_image_yaml(img)
        if "source" in yml:
            external.add(img)
            # Externally-sourced: fall back to image.yaml depends_on.
            for dep in yml.get("depends_on", []) or []:
                if isinstance(dep, str) and dep in local_images:
                    forward[img].add(dep)
            # External-sourced images are drawn with a dashed edge from BEACONRY_SRC.
            upstream_dashed.append(("BEACONRY_SRC", img))
            continue

        df = IMAGES_DIR / img / "Dockerfile"
        if not df.is_file():
            continue
        arg_defaults, froms, copy_stages = _parse_dockerfile(df)

        # Record the final-stage FROM resolution for FG-076 class-1-vs-2 lookup.
        if froms:
            final_target, _final_stage, _ = froms[-1]
            final_resolved = _resolve_target(final_target, arg_defaults, local_images)
            if final_resolved and final_resolved[0] != "scratch":
                final_src[img] = final_resolved

        # Map stage name → (resolved, has_content).
        stage_to_resolved: dict[str, tuple[tuple[str, str], bool]] = {}
        for target, stage, has_content in froms:
            resolved = _resolve_target(target, arg_defaults, local_images)
            if resolved is None:
                continue
            kind, name = resolved
            if kind == "scratch":
                pass  # no edge
            elif has_content:
                # Stage with content: solid edge (builder stage or runtime base).
                if kind == "local" and name != img:
                    forward[img].add(name)
                elif kind in {"upstream", "helper-upstream", "helper-local"}:
                    upstream_solid.append((name, img))
            # Stage without content is copy-only; the edge is emitted via the
            # COPY --from=<stage> loop below so we don't double-count.
            if stage:
                stage_to_resolved[stage] = (resolved, has_content)

        # COPY --from=<stage> edges — only for stages WITHOUT content
        # (those WITH content already produced a solid edge above).
        # NOTE: for FG-059's reverse-dep lookup we ALSO add dashed-local
        # deps into `forward` — a COPY-from overlay (scratch-base-trixie)
        # still means "when X changes, Y must rebuild."
        emitted_dashed: set[tuple[str, str]] = set()
        for stage in copy_stages:
            ent = stage_to_resolved.get(stage)
            if not ent:
                continue
            (kind, name), has_content = ent
            if has_content:
                continue  # solid already emitted
            if kind == "local" and name != img:
                key = (name, img)
                if key not in emitted_dashed:
                    dashed_local.append(key)
                    emitted_dashed.add(key)
                forward[img].add(name)  # FG-059 fan-out must include overlays
            elif kind in {"upstream", "helper-upstream", "helper-local"}:
                key = (name, img)
                if key not in emitted_dashed:
                    upstream_dashed.append(key)
                    emitted_dashed.add(key)

    return forward, dashed_local, upstream_solid, upstream_dashed, external, final_src


def _tier_of(image: str) -> str:
    if image in _UPSTREAM_HELPERS:
        return "upstream-helper"
    if image in _FORGE_MIRRORS:
        return "L0_5"
    if image in _PRE_BUILDERS:
        return "L1"
    if image in _FORGE_BUILDERS:
        return "L2"
    if image in _BASELINE:
        return "L3"
    return "L4"


def _style_of(image: str, external: set[str]) -> str:
    if image in _PRE_BUILDERS:
        return "prebuilder"
    if image in _FORGE_BUILDERS:
        return "builder"
    if image in _BASELINE:
        return "baseline"
    if image in external:
        return "external"
    # L4 split: slim vs scratch by name suffix (trixie-slim vs scratch-*)
    if "scratch" in image:
        return "scratch"
    return "slim"


def _source_node_id(url: str) -> str:
    """Stable mermaid-safe node id for an L0.1 source URL.

    Examples:
      github.com/bboortz/beaconry → SRC_GH_BBOORTZ_BEACONRY
      ziglang.org/download        → SRC_ZIGLANG_DOWNLOAD
    """
    sanitized = re.sub(r"[^a-zA-Z0-9]", "_", url).upper()
    sanitized = re.sub(r"^GITHUB_COM_", "GH_", sanitized)
    return f"SRC_{sanitized}"


def emit_mermaid_body(local_images: set[str]) -> str:
    """Just the ```mermaid ... ``` block (no surrounding markdown)."""
    forward, dashed_local, upstream_solid, upstream_dashed, external, final_src = build_full_graph(local_images)

    lines: list[str] = []
    lines.append("```mermaid")
    lines.append("%% Auto-generated by scripts/image_from_graph.py --emit=mermaid.")
    lines.append("%% Do NOT edit this block by hand; run `make dep-graph` to regenerate.")
    lines.append("%% Legend: solid --> FROM (builder stage or runtime base);")
    lines.append("%%         dashed -.-> COPY --from= (overlay / helper embed only).")
    lines.append("%% Node colors: upstream (gray), pre-builder (orange), builder (blue),")
    lines.append("%%              baseline (green), slim runtime (white), scratch runtime (yellow),")
    lines.append("%%              external-sourced (purple).")
    lines.append("graph TD")

    # Discover upstream nodes actually referenced.
    referenced_upstreams: set[str] = set()
    for up, _dst in upstream_solid:
        referenced_upstreams.add(up)
    for up, _dst in upstream_dashed:
        referenced_upstreams.add(up)

    # L0 subgraph.
    lines.append('    subgraph L0_upstream["Layer 0 — Upstream (external to Forge)"]')
    for up in sorted(referenced_upstreams):
        node_id, label = _UPSTREAM_NODE_IDS.get(up, (None, None))
        if node_id is None:
            continue
        lines.append(f'        {node_id}["{label}"]:::upstream')
    lines.append("    end")

    # L0.1 subgraph (FG-068 — upstream source repos / tarballs, not images).
    # Each source has dashed edges to its declared consumers (registered in
    # scripts/_upstream_sources.py, verified by verify-source-inventory.py).
    if _UPSTREAM_SOURCES:
        lines.append('    subgraph L0_1_sources["Layer 0.1 — Upstream sources (git clone / tarball; build-time only)"]')
        for src_url in sorted(_UPSTREAM_SOURCES):
            node_id = _source_node_id(src_url)
            label = src_url
            lines.append(f'        {node_id}["{label}"]:::upstream_source')
        lines.append("    end")

    # L0.5 subgraph (FG-066 — forge mirrors, zero-mod passthroughs).
    lines.append('    subgraph L0_5_mirrors["Layer 0.5 — Forge mirrors (zero-mod upstream passthroughs; publish-mirrors tier)"]')
    for name in sorted(_FORGE_MIRRORS):
        if name in local_images:
            # Node id can't contain "/"; derive <tier>_<leaf-dashes-to-under>
            # same way _local_id does below.
            tier, leaf = name.split("/", 1)
            node_id = f"{tier}_{leaf.replace('-', '_')}"
            lines.append(f'        {node_id}["{name}"]:::mirror')
    lines.append("    end")

    # L1 subgraph (pre-builders). FG-070: nested under pre-builder/<name>/,
    # emit as `<tier>_<leaf>[<label>]:::style` for mermaid-safe node ids.
    lines.append('    subgraph L1_prebuilders["Layer 1 — Forge pre-builders (publish-pre-builders)"]')
    for name in sorted(_PRE_BUILDERS):
        if name in local_images:
            if "/" in name:
                tier, leaf = name.split("/", 1)
                node_id = f"{tier}_{leaf.replace('-', '_')}"
                lines.append(f'        {node_id}["{name}"]:::prebuilder')
            else:
                lines.append(f"        {name}:::prebuilder")
    lines.append("    end")

    # L2 subgraph (builders). Nested post-FG-071 (images/builder/<lang>-trixie/).
    lines.append('    subgraph L2_builders["Layer 2 — Forge builders (publish-builders — never runtime)"]')
    for name in sorted(_FORGE_BUILDERS):
        if name in local_images:
            if "/" in name:
                tier, leaf = name.split("/", 1)
                node_id = f"{tier}_{leaf.replace('-', '_')}"
                lines.append(f'        {node_id}["{name}"]:::builder')
            else:
                lines.append(f"        {name}:::builder")
    lines.append("    end")

    # L3 subgraph (baseline).
    lines.append('    subgraph L3_baseline["Layer 3 — Forge baseline (publish-base — scratch overlay)"]')
    for name in sorted(_BASELINE):
        if name in local_images:
            if "/" in name:
                tier, leaf = name.split("/", 1)
                node_id = f"{tier}_{leaf.replace('-', '_')}"
                lines.append(f'        {node_id}["{name}"]:::baseline')
            else:
                lines.append(f"        {name}:::baseline")
    lines.append("    end")

    # L4 subgraph (runtimes: slim + scratch + external).
    lines.append('    subgraph L4_runtimes["Layer 4 — Runtimes (publish-base tail + publish-derivatives)"]')
    non_l4_classified = set(_PRE_BUILDERS) | set(_FORGE_BUILDERS) | set(_BASELINE) | set(_FORGE_MIRRORS)
    runtimes = sorted(img for img in local_images if img not in non_l4_classified)
    for name in runtimes:
        style = _style_of(name, external)
        lines.append(f"        {name}:::{style}")
    lines.append("    end")

    def _upstream_id(ref: str) -> str:
        node_id, _ = _UPSTREAM_NODE_IDS.get(ref, (ref, ref))
        return node_id

    def _local_id(name: str) -> str:
        # Mermaid node ids can't contain '/'. Nested paths: <tier>/<leaf>
        # → <tier>_<leaf-with-dashes-as-underscores>.
        # Historical FG-066: mirror/<leaf> encoded as `mirror_<leaf>`.
        # FG-069 generalizes: base/<leaf> → `base_<leaf>`, etc.
        if "/" in name:
            tier, leaf = name.split("/", 1)
            return f"{tier}_{leaf.replace('-', '_')}"
        return name

    # ------------------------------------------------------------------
    # FG-076: semantic edge styling.
    #
    # Every edge classified into one of 5 classes; shape + color + width
    # pinned per class via `linkStyle N` directives (indexed in emission
    # order). Tier-of-source color palette:
    #
    #   L0   external image      #D81B60  (red)
    #   L0.1 external source     #E65100  (orange)
    #   L0.5 mirror/*            #FBC02D  (yellow)
    #   L1   pre-builder/*       #43A047  (green)
    #   L2   builder/*           #1E88E5  (blue)
    #   L3   base/*              #6D4C41  (brown)
    #   L4   runtime (rare)      #424242  (dark grey)
    # ------------------------------------------------------------------
    _TIER_COLOR = {
        "L0":   "#D81B60",
        "L0.1": "#E65100",
        "L0.5": "#FBC02D",
        "L1":   "#43A047",
        "L2":   "#1E88E5",
        "L3":   "#6D4C41",
        "L4":   "#424242",
    }

    def _local_tier(name: str) -> str:
        if name in _FORGE_MIRRORS: return "L0.5"
        if name in _PRE_BUILDERS:  return "L1"
        if name in _FORGE_BUILDERS: return "L2"
        if name in _BASELINE:      return "L3"
        return "L4"

    # Class → (shape, width_px, extra_dasharray-or-None)
    # Class 1: thick solid, 5px   → FROM-parent (final-stage, trust-spine)
    # Class 2: thin  solid, 4px   → FROM builder-stage (content, discarded in child)
    # Class 3: dashed      , 4px  → COPY --from (overlay / tool)
    # Class 4: thick solid, 5px   → external L0 image FROM (fixed red)
    # Class 5: dashed      , 3px, dotted dasharray → L0.1 upstream source
    _CLASS_STYLE = {
        1: ("==>", 5, None),
        2: ("-->", 4, None),
        3: ("-.->", 4, None),
        4: ("==>", 5, None),
        5: ("-.->", 3, "1,3"),   # tight dot pattern
    }

    # Walk the pre-built edge sets in deterministic order + classify.
    # Returned tuple: (src_node_id, dst_node_id, class_num, color_hex).
    classified: list[tuple[str, str, int, str]] = []

    # Dedup set: (src_name, dst_name) pairs we've already classified as
    # an overlay (Class 3). If a FROM-with-content edge also appears for
    # the same pair, skip it (same pre-FG-076 dedup logic).
    dashed_pairs: set[tuple[str, str]] = {(src, dst) for src, dst in dashed_local}

    # Class 4: external upstream FROM (pre-builders + runtime exemptions).
    for src, dst in sorted(upstream_solid):
        classified.append((_upstream_id(src), _local_id(dst), 4, _TIER_COLOR["L0"]))

    # Class 1 / 2: forge-local FROM edges. `forward[img]` = {src local image}.
    # If src matches img's final-stage FROM resolution → Class 1 (trust spine).
    # Otherwise → Class 2 (builder-stage, content discarded).
    for img in sorted(forward):
        img_final = final_src.get(img)
        img_final_name = img_final[1] if (img_final and img_final[0] == "local") else None
        for dep in sorted(forward[img]):
            if (dep, img) in dashed_pairs:
                continue  # emitted as Class 3 below
            klass = 1 if dep == img_final_name else 2
            classified.append((_local_id(dep), _local_id(img), klass, _TIER_COLOR[_local_tier(dep)]))

    # Class 3: COPY --from (overlay / tool).
    for src, dst in sorted(dashed_local):
        classified.append((_local_id(src), _local_id(dst), 3, _TIER_COLOR[_local_tier(src)]))
    # Upstream dashed = L0 external images used as COPY-from source (hc, grype).
    # Exclude pre-FG-076 BEACONRY_SRC marker — the L0.1 _UPSTREAM_SOURCES loop
    # emits those as Class 5 instead (avoids double-rendering).
    for src, dst in sorted(upstream_dashed):
        if src.startswith("BEACONRY_SRC"):
            continue
        classified.append((_upstream_id(src), _local_id(dst), 3, _TIER_COLOR["L0"]))

    # Class 5: L0.1 upstream source → consumer.
    if _UPSTREAM_SOURCES:
        for src_url in sorted(_UPSTREAM_SOURCES):
            node = _source_node_id(src_url)
            for consumer in sorted(_UPSTREAM_SOURCES[src_url]):
                if consumer in local_images:
                    classified.append((node, _local_id(consumer), 5, _TIER_COLOR["L0.1"]))

    # Emit legend subgraph FIRST — it consumes 5 edge indices; main-graph
    # linkStyle indices start at 5 and are offset accordingly.
    lines.append("")
    lines.append("    %% FG-076 legend — 5 edge classes × tier-of-source palette")
    lines.append('    subgraph Legend["Edge legend (shape = relationship · color = tier of source)"]')
    lines.append("        direction LR")
    lines.append('        L_C1_SRC[" "]:::legend_node')
    lines.append('        L_C1_DST["Class 1 · FROM-parent (final-stage; trust + CVEs propagate)"]:::legend_node')
    lines.append('        L_C2_SRC[" "]:::legend_node')
    lines.append('        L_C2_DST["Class 2 · FROM builder-stage (content discarded in child)"]:::legend_node')
    lines.append('        L_C3_SRC[" "]:::legend_node')
    lines.append('        L_C3_DST["Class 3 · COPY --from (overlay / tool)"]:::legend_node')
    lines.append('        L_C4_SRC[" "]:::legend_node')
    lines.append('        L_C4_DST["Class 4 · external upstream image (L0, red)"]:::legend_node')
    lines.append('        L_C5_SRC[" "]:::legend_node')
    lines.append('        L_C5_DST["Class 5 · L0.1 upstream source (orange, build-time clone/tarball)"]:::legend_node')
    lines.append("        L_C1_SRC ==> L_C1_DST")
    lines.append("        L_C2_SRC --> L_C2_DST")
    lines.append("        L_C3_SRC -.-> L_C3_DST")
    lines.append("        L_C4_SRC ==> L_C4_DST")
    lines.append("        L_C5_SRC -.-> L_C5_DST")
    lines.append("    end")

    # Emit the classified edges + linkStyle lines.
    lines.append("")
    lines.append("    %% FG-076 classified edges (shape + color encode semantic class + source tier)")
    for src_id, dst_id, klass, _color in classified:
        shape, _w, _da = _CLASS_STYLE[klass]
        lines.append(f"    {src_id} {shape} {dst_id}")

    # linkStyle directives. Legend edges first (indices 0..4), then main
    # graph edges (indices 5..5+N-1).
    lines.append("")
    lines.append("    %% FG-076 linkStyle pins — one per emitted edge, in emission order")
    # Legend edge styles.
    for legend_class in (1, 2, 3, 4, 5):
        shape, width, dasharray = _CLASS_STYLE[legend_class]
        legend_idx = legend_class - 1
        color = _TIER_COLOR["L0"] if legend_class == 4 else (
            _TIER_COLOR["L0.1"] if legend_class == 5 else _TIER_COLOR["L3"]  # sample color for legend
        )
        extras = f",stroke-dasharray: {dasharray}" if dasharray else ""
        lines.append(f"    linkStyle {legend_idx} stroke:{color},stroke-width:{width}px{extras};")
    # Main-graph edges.
    for i, (_src, _dst, klass, color) in enumerate(classified, start=5):
        shape, width, dasharray = _CLASS_STYLE[klass]
        extras = f",stroke-dasharray: {dasharray}" if dasharray else ""
        lines.append(f"    linkStyle {i} stroke:{color},stroke-width:{width}px{extras};")

    # Node :::class styling (unchanged — these style the boxes, not the edges).
    lines.append("")
    lines.append("    %% Node styling")
    lines.append("    classDef upstream   fill:#eeeeee,stroke:#999,stroke-width:1px,color:#333;")
    lines.append("    classDef upstream_source fill:#fef3c7,stroke:#a16207,stroke-width:1px,color:#713f12,font-style:italic;")
    lines.append("    classDef prebuilder fill:#fed7aa,stroke:#c2410c,stroke-width:2px,color:#7c2d12;")
    lines.append("    classDef builder    fill:#dbeafe,stroke:#1e40af,stroke-width:2px,color:#1e3a8a;")
    lines.append("    classDef baseline   fill:#bbf7d0,stroke:#166534,stroke-width:2px,color:#14532d;")
    lines.append("    classDef slim       fill:#ffffff,stroke:#333,stroke-width:1px,color:#111;")
    lines.append("    classDef scratch    fill:#fef3c7,stroke:#b45309,stroke-width:1px,color:#78350f;")
    lines.append("    classDef external   fill:#ede9fe,stroke:#6d28d9,stroke-width:1px,color:#4c1d95;")
    lines.append("    classDef mirror     fill:#99f6e4,stroke:#0f766e,stroke-width:2px,color:#134e4a;")
    lines.append("    classDef legend_node fill:#ffffff,stroke:#999,stroke-width:1px,color:#333,font-size:11px;")
    lines.append("```")

    return "\n".join(lines) + "\n"


def emit_mermaid(local_images: set[str]) -> str:
    """Emit the hybrid layout: SVG image + collapsible mermaid source.

    GitHub mobile app doesn't render mermaid code blocks, so the SVG is
    the primary visual. The mermaid source lives inside a <details>
    block so operators can still copy/edit the authoritative source.
    """
    body = emit_mermaid_body(local_images)
    lines: list[str] = []
    lines.append("<!-- Auto-generated; do NOT edit this block. Run `make dep-graph` to regenerate. -->")
    lines.append("![Image dependency graph](image-dependency-graph.svg)")
    lines.append("")
    lines.append("<details>")
    lines.append("<summary>mermaid source (editable truth — GitHub desktop renders this live; mobile shows the SVG above)</summary>")
    lines.append("")
    lines.append(body.rstrip("\n"))
    lines.append("")
    lines.append("</details>")
    return "\n".join(lines) + "\n"


MARKER_START = "<!-- GENERATED:dep-graph START — regenerate with `make dep-graph` -->"
MARKER_END = "<!-- GENERATED:dep-graph END -->"


def write_mermaid_into(path: Path, mermaid: str) -> None:
    content = path.read_text()
    if MARKER_START not in content or MARKER_END not in content:
        sys.stderr.write(
            f"{path}: missing GENERATED markers. Add\n"
            f"  {MARKER_START}\n"
            f"  <mermaid block>\n"
            f"  {MARKER_END}\n"
            f"around the mermaid block first.\n"
        )
        sys.exit(2)
    pre, rest = content.split(MARKER_START, 1)
    _old, post = rest.split(MARKER_END, 1)
    new = f"{pre}{MARKER_START}\n{mermaid}{MARKER_END}{post}"
    path.write_text(new)


# ---------------------------------------------------------------------------
# FG-059 — reverse-dep graph (unchanged default behavior).


def reverse_graph(forward: dict[str, set[str]]) -> dict[str, set[str]]:
    reverse: dict[str, set[str]] = {img: set() for img in forward}
    for src, targets in forward.items():
        for t in targets:
            reverse.setdefault(t, set()).add(src)
    return reverse


def detect_cycles(forward: dict[str, set[str]]) -> list[list[str]]:
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in forward}
    cycles: list[list[str]] = []
    stack: list[str] = []

    def visit(n: str) -> None:
        color[n] = GRAY
        stack.append(n)
        for m in sorted(forward.get(n, ())):
            if color.get(m, WHITE) == GRAY:
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
    parser = argparse.ArgumentParser(description="Image dependency graph emitter (FG-059 + FG-064).")
    parser.add_argument("--deps", metavar="IMAGE", help="Print one dep per line for IMAGE (reverse-graph)")
    parser.add_argument("--emit", choices=["reverse-json", "mermaid"], default="reverse-json")
    parser.add_argument("--write", metavar="FILE", help="With --emit=mermaid: rewrite FILE between GENERATED markers")
    args = parser.parse_args()

    local_images = all_images()

    if args.emit == "mermaid":
        mermaid = emit_mermaid(local_images)
        if args.write:
            write_mermaid_into(Path(args.write), mermaid)
            return 0
        sys.stdout.write(mermaid)
        return 0

    # Default: FG-059 reverse-JSON (back-compat).
    forward, _dashed_l, _upstream_s, _upstream_d, _external, _final_src = build_full_graph(local_images)
    cycles = detect_cycles(forward)
    if cycles:
        sys.stderr.write("image_from_graph: cycle(s) detected in Dockerfile FROM graph:\n")
        for c in cycles:
            sys.stderr.write("  " + " -> ".join(c) + "\n")
        return 2

    reverse = reverse_graph(forward)

    if args.deps:
        for dep in sorted(reverse.get(args.deps, ())):
            print(dep)
        return 0

    out = {k: sorted(v) for k, v in sorted(reverse.items()) if v}
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
