#!/usr/bin/env python3
# FG-064 — Dockerfile conformance lint.
#
# Enforces a parser-friendly format across images/*/Dockerfile so
# scripts/image_from_graph.py can derive the full dependency graph
# with zero drift. Rules:
#
#   1. ARG *_REF naming: every `ARG <NAME>_REF=...` NAME is in a known
#      allowlist (grep-ability + predictable parsing). Non-_REF ARGs
#      (like GO_BASE, NODE_BASE, SYFT_SRC — dedicated-toolchain
#      exemptions) are NOT subject to this rule but ARE subject to
#      rules 2-3 via their FROM usage.
#   2. Every `FROM ${X}` references an ARG declared in the same
#      Dockerfile. The ARG's default must resolve to one of:
#        - ghcr.io/bboortz/<image>:<tag>, <image> a local images/ dir
#          or the known 'hc' helper
#        - forge-local/<image>:<tag>, <image> a local images/ dir
#          (dev-loop fallback — scratch-base-trixie)
#        - a Docker Hub upstream in _UPSTREAM_ALLOWLIST
#        - a helper upstream in _HELPER_UPSTREAM_ALLOWLIST (syft)
#   3. Every literal `^FROM <upstream>` is either `scratch` or in
#      _UPSTREAM_ALLOWLIST. No new upstream drift.
#   4. Every `COPY --from=<name>` references a stage declared by an
#      earlier `FROM ... AS <name>` in the same Dockerfile.
#   5. Every intermediate FROM (all but the last) carries
#      `AS <stage-name>` — no anonymous intermediate stages.
#   6. No intra-layer FROM edge: images in the same role tier
#      (pre-builders / builders / runtime) cannot FROM each other.
#
# Exit codes: 0 pass, 1 rule violated, 2 IO / internal error.

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"

# Mirrors scripts/discover-images.sh _PRE_BUILDERS / _FORGE_BUILDERS.
# Keep in sync via the FG-064 acceptance test §1.
_PRE_BUILDERS = {
    "debian-slim-sid",
    "debian-slim-trixie",
    "node-slim-trixie",
    "python-slim-trixie",
    "ubuntu-slim-noble",
}
_FORGE_BUILDERS = {
    "forge-builder-go-trixie",
    "forge-builder-node-trixie",
    "forge-builder-python-trixie",
}
_BASELINE = {"scratch-base-trixie"}
# Upstream helpers (COPY-from image layer forge-publishes but aren't under images/).
# Treated as L0 for layering — not a runtime, not a builder.
_UPSTREAM_HELPERS = {"hc"}

# Recognized ARG *_REF= names. Any new _REF ARG must be added here first
# (and probably mirrored in scripts/image_from_graph.py). Keeping the
# list small is the point — grep-ability + predictable parsing.
_KNOWN_REF_ARGS = {
    "FORGE_BUILDER_REF",         # forge-builder-python-trixie (legacy; kept for scratch-base-trixie + scratch runtimes)
    "FORGE_BUILDER_GO_REF",      # forge-builder-go-trixie
    "FORGE_BUILDER_NODE_REF",    # forge-builder-node-trixie
    "SCRATCH_BASE_REF",          # scratch-base-trixie
    "DEBIAN_SLIM_REF",           # debian-slim-trixie
    "DEBIAN_SLIM_SID_REF",       # debian-slim-sid (zero consumers today; reserved)
    "PYTHON_SLIM_REF",           # python-slim-trixie
    "UBUNTU_SLIM_NOBLE_REF",     # ubuntu-slim-noble
    "NODE_SLIM_REF",             # node-slim-trixie
    "HC_REF",                    # ghcr.io/bboortz/hc (healthcheck embed)
}

# Upstream Docker Hub tags allowed as literal `FROM` or as the default of
# a non-_REF ARG (dedicated-toolchain exemption).
_UPSTREAM_ALLOWLIST = {
    "debian:trixie-slim",
    "debian:sid-slim",
    "python:3.14-slim-trixie",
    "ubuntu:24.04",
    "node:24-trixie-slim",
    "golang:1.27-trixie",
    "postgres:18",
}

# Upstream helpers (not language bases; tools pulled as a stage).
_HELPER_UPSTREAM_ALLOWLIST = {
    "docker.io/anchore/syft:latest",
    "anchore/syft:latest",
}

_ARG_RE = re.compile(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*=\s*(\S+))?\s*$")
_FROM_RE = re.compile(r"^\s*FROM\s+(\S+)(?:\s+AS\s+(\S+))?\s*$")
_COPY_FROM_RE = re.compile(r"^\s*COPY\s+--from=([A-Za-z0-9_][A-Za-z0-9_-]*)\b")
_ARG_SUBST_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")
_GHCR_REF_RE = re.compile(r"^ghcr\.io/bboortz/([a-z0-9][a-z0-9-]*):[a-zA-Z0-9._-]+$")
_FORGE_LOCAL_REF_RE = re.compile(r"^forge-local/([a-z0-9][a-z0-9-]*):[a-zA-Z0-9._-]+$")


def _local_images() -> set[str]:
    return {p.name for p in IMAGES_DIR.iterdir() if p.is_dir() and (p / "image.yaml").is_file()}


def _tier_of(image: str) -> str:
    if image in _UPSTREAM_HELPERS:
        return "upstream-helper"
    if image in _PRE_BUILDERS:
        return "pre-builder"
    if image in _FORGE_BUILDERS:
        return "builder"
    if image in _BASELINE:
        return "baseline"
    return "runtime"


def _classify_arg_default(default: str, local_images: set[str]) -> tuple[str, str | None]:
    """Return (kind, resolved_target) for an ARG default string.

    kind is one of 'local', 'upstream', 'helper', 'unknown'; resolved_target
    is the image dir name (local), the upstream tag (upstream / helper), or
    None (unknown).
    """
    if m := _GHCR_REF_RE.match(default):
        tgt = m.group(1)
        if tgt in local_images or tgt == "hc":
            return "local", tgt
        return "unknown", None
    if m := _FORGE_LOCAL_REF_RE.match(default):
        tgt = m.group(1)
        if tgt in local_images:
            return "local", tgt
        return "unknown", None
    if default in _UPSTREAM_ALLOWLIST:
        return "upstream", default
    if default in _HELPER_UPSTREAM_ALLOWLIST:
        return "helper", default
    return "unknown", None


def _check_file(df: Path, local_images: set[str]) -> list[str]:
    errors: list[str] = []
    try:
        content = df.read_text()
    except OSError as exc:
        return [f"{df}: read failed: {exc}"]

    image_name = df.parent.name
    my_tier = _tier_of(image_name)
    rel = df.relative_to(REPO_ROOT).as_posix()

    # Pass 1: collect ARG decls + FROMs + COPY --from= refs.
    arg_defaults: dict[str, str | None] = {}
    froms: list[tuple[int, str, str | None]] = []  # (lineno, raw_target, stage_or_none)
    copy_from_refs: list[tuple[int, str]] = []     # (lineno, stage-name)

    for i, raw in enumerate(content.splitlines(), start=1):
        line = raw.split("#", 1)[0].rstrip()
        if not line:
            continue
        if m := _ARG_RE.match(line):
            arg_defaults[m.group(1)] = m.group(2)  # default may be None (no default)
            continue
        if m := _FROM_RE.match(line):
            froms.append((i, m.group(1), m.group(2)))
            continue
        if m := _COPY_FROM_RE.match(line):
            copy_from_refs.append((i, m.group(1)))

    # Rule 1: ARG *_REF naming allowlist.
    for name, _default in arg_defaults.items():
        if name.endswith("_REF") and name not in _KNOWN_REF_ARGS:
            errors.append(
                f"{rel}: unknown ARG ref convention '{name}'. "
                f"Allowed _REF ARGs: {sorted(_KNOWN_REF_ARGS)}. "
                f"Add to scripts/verify-dockerfile-conformance.py + "
                f"scripts/image_from_graph.py if this is a new category."
            )

    # Collect edges for rule 6 (intra-layer check).
    edge_targets: set[str] = set()

    # Rule 2+3: every FROM resolves correctly.
    for lineno, target, _stage in froms:
        if target == "scratch":
            continue
        if subst := _ARG_SUBST_RE.match(target):
            arg_name = subst.group(1)
            if arg_name not in arg_defaults:
                errors.append(
                    f"{rel}:{lineno}: FROM {target} — ARG {arg_name} is not declared in this Dockerfile"
                )
                continue
            default = arg_defaults[arg_name]
            if not default:
                # ARG without default — build-arg must be supplied externally. OK
                # for build-time overrides, but we need SOME default to classify the
                # tier. Defaults are mandatory for ARGs used in FROM.
                errors.append(
                    f"{rel}:{lineno}: FROM {target} — ARG {arg_name} has no default; "
                    f"every FROM-indirecting ARG must declare a default for graph classification"
                )
                continue
            kind, resolved = _classify_arg_default(default, local_images)
            if kind == "unknown":
                errors.append(
                    f"{rel}:{lineno}: FROM {target} — ARG {arg_name}={default!r} "
                    f"does not resolve to a local images/ dir, 'hc', or an "
                    f"allowlisted upstream. Expected: "
                    f"ghcr.io/bboortz/<image>:<tag> | forge-local/<image>:<tag> | "
                    f"one of {sorted(_UPSTREAM_ALLOWLIST | _HELPER_UPSTREAM_ALLOWLIST)}"
                )
                continue
            if kind == "local" and resolved:
                edge_targets.add(resolved)
            continue
        # Literal FROM — must be in the upstream allowlist (or a helper).
        if target not in _UPSTREAM_ALLOWLIST and target not in _HELPER_UPSTREAM_ALLOWLIST:
            errors.append(
                f"{rel}:{lineno}: literal FROM {target} is not in the "
                f"dedicated-toolchain / pre-builder upstream allowlist. "
                f"Allowed literals: {sorted(_UPSTREAM_ALLOWLIST | _HELPER_UPSTREAM_ALLOWLIST)} "
                f"or use ARG-indirect ${{<NAME>}}."
            )

    # Rule 4: COPY --from=<name> resolves to a declared stage.
    stage_names: set[str] = {stage for _, _, stage in froms if stage}
    for lineno, stage in copy_from_refs:
        if stage not in stage_names:
            errors.append(
                f"{rel}:{lineno}: COPY --from={stage} — no FROM ... AS {stage} "
                f"declared earlier in this Dockerfile. Declared stages: "
                f"{sorted(stage_names) or '(none)'}"
            )

    # Rule 5: intermediate FROMs must have AS <stage>.
    if len(froms) >= 2:
        for lineno, target, stage in froms[:-1]:
            if stage is None:
                errors.append(
                    f"{rel}:{lineno}: FROM {target} is an intermediate stage "
                    f"and must declare AS <stage-name> (no anonymous stages)."
                )

    # Rule 6: no intra-layer FROM edge.
    for target_image in edge_targets:
        target_tier = _tier_of(target_image)
        if target_tier == my_tier:
            errors.append(
                f"{rel}: intra-layer FROM edge to {target_image} — both this image "
                f"({image_name}) and the target are in the '{my_tier}' tier. "
                f"Layered dep-graph (FG-064) requires downward-only edges."
            )

    return errors


def main() -> int:
    local_images = _local_images()
    all_errors: list[str] = []
    for df in sorted(IMAGES_DIR.glob("*/Dockerfile")):
        all_errors.extend(_check_file(df, local_images))

    if all_errors:
        sys.stderr.write("verify-dockerfile-conformance: FAIL\n")
        for e in all_errors:
            sys.stderr.write(f"  ✗ {e}\n")
        return 1

    n = sum(1 for _ in IMAGES_DIR.glob("*/Dockerfile"))
    print(f"verify-dockerfile-conformance: ok ({n} Dockerfile(s) conform to FG-064).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
