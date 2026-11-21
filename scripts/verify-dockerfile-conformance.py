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
# FG-067: allow FORGE_IMAGES_DIR override so the FG-067 acceptance test can
# exercise Rule 11 against a synthetic images/source/ tree without touching
# the real images/ root. Default stays repo-local.
import os  # noqa: E402

_images_override = os.environ.get("FORGE_IMAGES_DIR")
IMAGES_DIR = Path(_images_override).resolve() if _images_override else (REPO_ROOT / "images")

# Mirrors scripts/discover-images.sh _PRE_BUILDERS / _FORGE_BUILDERS.
# Keep in sync via the FG-064 acceptance test §1.
_PRE_BUILDERS = {
    "pre-builder/debian-slim-sid",
    "pre-builder/debian-slim-trixie",
    "pre-builder/go-slim-trixie",
    "pre-builder/node-slim-trixie",
    "pre-builder/python-slim-trixie",
    "pre-builder/ubuntu-slim-noble",
    "pre-builder/zig-slim-trixie",
    "pre-builder/alpine-3",        # FG-079
    "pre-builder/archlinux",       # FG-081
}
# FG-066: forge mirror tier. Members under `images/mirror/<name>/` are
# zero-mod forge-signed passthroughs of external upstream tool images.
# Shape enforced by Rule 10 below.
_FORGE_MIRRORS = {
    "mirror/syft",
}
_FORGE_BUILDERS = {
    "builder/go-trixie",
    "builder/node-trixie",
    "builder/python-trixie",
    "builder/zig-trixie",
}
_BASELINE = {
    "base/scratch-trixie",
    "base/python-scratch-trixie",
    "base/python-slim-trixie",
    "base/debian-slim-trixie",   # FG-077
    "base/ubuntu-slim-noble",    # FG-077
    "base/node-slim-trixie",     # FG-077
    "base/alpine-3",             # FG-079
    "base/scratch-alpine-3",     # FG-080
    "base/archlinux",            # FG-081
}
# Upstream helpers (COPY-from image layer forge-publishes but aren't under images/).
# Treated as L0 for layering — not a runtime, not a builder.
_UPSTREAM_HELPERS = {"hc"}

# Recognized ARG *_REF= names. Any new _REF ARG must be added here first
# (and probably mirrored in scripts/image_from_graph.py). Keeping the
# list small is the point — grep-ability + predictable parsing.
_KNOWN_REF_ARGS = {
    "BUILDER_PYTHON_REF",        # builder/python-trixie (FG-071; renamed from FORGE_BUILDER_REF)
    "BUILDER_GO_REF",            # builder/go-trixie (FG-071; renamed from FORGE_BUILDER_GO_REF)
    "BUILDER_NODE_REF",          # builder/node-trixie (FG-071; renamed from FORGE_BUILDER_NODE_REF)
    "BUILDER_ZIG_REF",           # builder/zig-trixie (FG-071; reserved; no consumer yet)
    "SCRATCH_BASE_REF",          # scratch-base-trixie
    "DEBIAN_SLIM_REF",           # debian-slim-trixie
    "DEBIAN_SLIM_SID_REF",       # debian-slim-sid (zero consumers today; reserved)
    "PYTHON_SLIM_REF",           # python-slim-trixie
    "UBUNTU_SLIM_NOBLE_REF",     # ubuntu-slim-noble
    "NODE_SLIM_REF",             # node-slim-trixie
    "GO_SLIM_REF",               # go-slim-trixie (FG-065)
    "ZIG_SLIM_REF",              # zig-slim-trixie (FG-072)
    "SYFT_REF",                  # mirror/syft (FG-066)
    "HC_REF",                    # ghcr.io/bboortz/hc (healthcheck embed)
    "BASE_DEBIAN_SLIM_REF",      # base/debian-slim-trixie (FG-077)
    "BASE_UBUNTU_SLIM_NOBLE_REF",# base/ubuntu-slim-noble (FG-077)
    "BASE_NODE_SLIM_REF",        # base/node-slim-trixie (FG-077)
    "ALPINE_REF",                # pre-builder/alpine-3 (FG-079; internal)
    "BASE_ALPINE_REF",           # base/alpine-3 (FG-079; public API)
    "BASE_SCRATCH_ALPINE_REF",   # base/scratch-alpine-3 (FG-080; scratch-musl overlay)
    "ARCHLINUX_REF",             # pre-builder/archlinux (FG-081; internal)
    "BASE_ARCHLINUX_REF",        # base/archlinux (FG-081; public API)
}

# Upstream Docker Hub tags allowed as literal `FROM` or as the default of
# a non-_REF ARG. These may only appear in the specific images allowed to
# consume them (see _UPSTREAM_FROM_ALLOWED_BY_IMAGE).
_UPSTREAM_ALLOWLIST = {
    "debian:trixie-slim",
    "debian:sid-slim",
    "python:3.14-slim-trixie",
    "ubuntu:24.04",
    "node:24-trixie-slim",
    "golang:1.27-trixie",
    "postgres:18",
    "alpine:3",                  # FG-079 — Alpine OS family
    "archlinux:latest",          # FG-081 — Arch Linux OS family
}

# FG-065 Rule 8: literal `FROM <upstream>` is ALLOWED only in these images.
# Pre-builders are auto-allowed (each one exists exactly to consume its
# upstream). postgres-slim-trixie is a documented exemption — rebuilding
# postgres from source is too big (memory/docker-standard.md).
_UPSTREAM_FROM_RUNTIME_EXEMPTIONS = {
    "postgres-slim-trixie": "postgres:18",
}

# FG-072 Rule 6 exemption: intra-tier FROM edges inside the pre-builder
# layer are normally forbidden (layered-graph invariant), but Zig has no
# Debian-based Docker Hub upstream so `zig-slim-trixie` necessarily FROMs
# `debian-slim-trixie`. Keeping this edge preserves FG-042's single-
# upstream-consumer rule (if zig-slim-trixie FROMed `debian:trixie-slim`
# directly, that upstream would gain a second forge consumer + the drift-
# guard _EXPECTED would need to bump). Any future `<lang>-slim-trixie`
# whose upstream isn't on Docker Hub reuses this exemption; new entries
# must be named here explicitly (no wildcard — keep it audit-grep-able).
_INTRA_LAYER_EXEMPTIONS: set[tuple[str, str]] = {
    ("pre-builder/zig-slim-trixie", "pre-builder/debian-slim-trixie"),
    # FG-069: base/python-scratch-trixie overlays base/scratch-trixie. Both are
    # L3 "scratch-assembled runtime foundations", and the python overlay
    # legitimately COPYs the scratch-trixie overlay as its substrate.
    # Narrow within-tier edge, same pattern as zig → debian-slim.
    # FG-075: renamed from base/python-trixie.
    ("base/python-scratch-trixie", "base/scratch-trixie"),
    # FG-077: 3 new base/*-slim-trixie siblings FROM their respective
    # pre-builder/*-slim-trixie counterparts. L3 → L1 edges (not strictly
    # intra-layer), but allowed as narrow named exemptions — each new base/
    # exists to layer /hc + USER 65532 on top of the pre-builder for
    # external consumers while keeping the pre-builder/ tier internal.
    ("base/debian-slim-trixie", "pre-builder/debian-slim-trixie"),
    ("base/ubuntu-slim-noble", "pre-builder/ubuntu-slim-noble"),
    ("base/node-slim-trixie", "pre-builder/node-slim-trixie"),
    # FG-075 (already present in the list above for python, re-stated here
    # for the inventory): base/python-slim-trixie FROMs pre-builder/python-
    # slim-trixie.
    ("base/python-slim-trixie", "pre-builder/python-slim-trixie"),
    # FG-079: base/alpine-3 FROMs pre-builder/alpine-3 — same pattern as
    # the FG-077 Debian/Ubuntu/Node siblings. Alpine is a new OS family.
    ("base/alpine-3", "pre-builder/alpine-3"),
    # FG-080: base/scratch-alpine-3's builder stage FROMs base/alpine-3.
    # L3 → L3 intra-tier edge (same as base/python-scratch-trixie overlaying
    # base/scratch-trixie). Narrow named exemption.
    ("base/scratch-alpine-3", "base/alpine-3"),
    # FG-081: base/archlinux FROMs pre-builder/archlinux — same pattern as
    # FG-079's base/alpine-3 → pre-builder/alpine-3. Third OS family.
    ("base/archlinux", "pre-builder/archlinux"),
}

# Upstream helpers (not language bases; tools pulled as a stage).
# FG-066 emptied this — syft was the only entry; it's now forge-signed
# via `mirror/syft` per the arch.forge-mirror-image invariant. Kept
# as an empty set so future helpers (if any genuinely-unavoidable
# upstream helper appears) can land here before being mirrored.
_HELPER_UPSTREAM_ALLOWLIST: set[str] = set()

_ARG_RE = re.compile(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*=\s*(\S+))?\s*$")
_FROM_RE = re.compile(r"^\s*FROM\s+(\S+)(?:\s+AS\s+(\S+))?\s*$")
_COPY_FROM_RE = re.compile(r"^\s*COPY\s+--from=([A-Za-z0-9_][A-Za-z0-9_-]*)\b")
_ARG_SUBST_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")
# FG-066: allow nested repo paths (`mirror/<name>`) in ghcr.io / forge-local refs.
_GHCR_REF_RE = re.compile(r"^ghcr\.io/bboortz/([a-z0-9][a-z0-9-]*(?:/[a-z0-9][a-z0-9-]*)?):[a-zA-Z0-9._-]+$")
_FORGE_LOCAL_REF_RE = re.compile(r"^forge-local/([a-z0-9][a-z0-9-]*(?:/[a-z0-9][a-z0-9-]*)?):[a-zA-Z0-9._-]+$")
# FG-065 Rule 9: Docker Hub / ghcr-library URL grep. Catches binary/HTTP pulls
# in RUN/COPY/ADD lines that would sneak past FROM linting.
_DOCKER_HUB_URL_RE = re.compile(r"\b(docker\.io|hub\.docker\.com|registry-1\.docker\.io|ghcr\.io/library)\b")


def _local_images() -> set[str]:
    # FG-066: walk 2 levels deep so nested `images/mirror/<name>/` dirs
    # surface as `mirror/<name>` (canonical form through the tooling).
    out: set[str] = set()
    for p in IMAGES_DIR.iterdir():
        if not p.is_dir():
            continue
        if (p / "image.yaml").is_file():
            out.add(p.name)
            continue
        # One level of nesting (mirror/<name>, future tiers/<name>).
        for sub in p.iterdir():
            if sub.is_dir() and (sub / "image.yaml").is_file():
                out.add(f"{p.name}/{sub.name}")
    return out


def _tier_of(image: str) -> str:
    if image in _UPSTREAM_HELPERS:
        return "upstream-helper"
    if image in _FORGE_MIRRORS:
        return "mirror"
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

    # FG-066: canonical image name is the full path under images/ (so
    # nested mirror/<name> paths survive). Flat: `<dir>`. Nested:
    # `<tier>/<dir>`.
    _rel_parent = df.parent.relative_to(IMAGES_DIR).as_posix()
    image_name = _rel_parent
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
        # FG-066: mirror/* images are EXEMPT from this rule — they exist
        # precisely to re-publish an arbitrary upstream tool image under
        # forge signature. Rule 10 below enforces mirror-tier zero-mod.
        if my_tier == "mirror":
            continue
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
            # FG-072: explicit exemption allowlist for pre-builders whose
            # upstream isn't on Docker Hub (first case: zig-slim-trixie →
            # debian-slim-trixie).
            if (image_name, target_image) in _INTRA_LAYER_EXEMPTIONS:
                continue
            errors.append(
                f"{rel}: intra-layer FROM edge to {target_image} — both this image "
                f"({image_name}) and the target are in the '{my_tier}' tier. "
                f"Layered dep-graph (FG-064) requires downward-only edges."
            )

    # Rule 7 (FG-065 + FG-071): builder/<lang>-trixie's runtime (last) FROM MUST
    # resolve to a forge-rooted image, not an upstream. Builder-stage copy-
    # sources (syft, hc) are allowed earlier — this rule only checks the
    # last FROM, which is the "runtime" / default stage of the builder.
    if image_name in _FORGE_BUILDERS and froms:
        # froms[-1] = (lineno, target, stage) per the parser above.
        _ln, last_target, _last_stage = froms[-1]
        resolved_kind: str | None = None
        if last_target != "scratch":
            if m := _ARG_SUBST_RE.match(last_target):
                default = arg_defaults.get(m.group(1))
                if default:
                    resolved_kind, _ = _classify_arg_default(default, local_images)
            else:
                resolved_kind, _ = _classify_arg_default(last_target, local_images)
        if resolved_kind in {"upstream", "helper-upstream"}:
            errors.append(
                f"{rel}: builder image's last FROM resolves to an upstream "
                f"({last_target}) — must FROM a forge-rooted pre-builder instead "
                f"(FG-065 arch.language-family-image-pair invariant: every "
                f"builder/<lang>-trixie dogfoods its sibling pre-builder/"
                f"<lang>-slim-trixie pre-builder)."
            )

    # Rule 8 (FG-065): literal `FROM <upstream>` (any line, not just the last)
    # is ONLY allowed in pre-builder images + the explicit runtime-exemption
    # allowlist. Every other image must FROM a forge-rooted base. This is
    # the generalization of Rule 7 — it catches upstream FROMs in slim
    # runtimes, scratch runtimes, dual-builder intermediate stages, etc.
    #
    # Pre-builders are auto-exempt (they EXIST to consume their upstream).
    # postgres-slim-trixie is an explicit runtime exemption (rebuilding
    # postgres from source is too big — memory/docker-standard.md).
    if image_name not in _PRE_BUILDERS:
        allowed_literal = _UPSTREAM_FROM_RUNTIME_EXEMPTIONS.get(image_name)
        for lineno, target, _stage in froms:
            if target in _UPSTREAM_ALLOWLIST and target != allowed_literal:
                errors.append(
                    f"{rel}:{lineno}: literal FROM {target} is not allowed in "
                    f"non-pre-builder image '{image_name}'. Allowed patterns: "
                    f"(a) FROM a forge-rooted pre-builder via "
                    f"ARG <X>_REF=ghcr.io/bboortz/<X>:<tag>; "
                    f"(b) scratch; (c) explicit runtime exemption "
                    f"(currently only {sorted(_UPSTREAM_FROM_RUNTIME_EXEMPTIONS)}). "
                    f"FG-065 invariant: forge images FROM forge images, upstreams "
                    f"are consumed exactly once (by their pre-builder)."
                )

    # Rule 10 (FG-066): mirror/* Dockerfiles are zero-mod passthroughs.
    # Allowed directives: FROM, ARG, LABEL, COPY --from=<stage>. Every
    # other directive (RUN / ENV / WORKDIR / CMD / USER / ADD / EXPOSE /
    # HEALTHCHECK / VOLUME / SHELL / STOPSIGNAL / ONBUILD / ENTRYPOINT)
    # is a lint failure — arch.forge-mirror-image invariant.
    if my_tier == "mirror":
        _MIRROR_ALLOWED_DIRECTIVES = {"FROM", "ARG", "LABEL", "COPY"}
        for i, raw in enumerate(content.splitlines(), start=1):
            line = raw.split("#", 1)[0].rstrip()
            if not line or line.startswith(("#", " ", "\t")):
                continue
            # Line continuations (lines that are a continuation of a
            # previous directive starting with <space>|<tab>) — skip.
            directive = line.split(None, 1)[0].upper()
            if directive in _MIRROR_ALLOWED_DIRECTIVES:
                # Extra constraint for COPY: only `COPY --from=<stage>` form.
                if directive == "COPY" and "--from=" not in line:
                    errors.append(
                        f"{rel}:{i}: mirror image uses `COPY` without `--from=` — "
                        f"only COPY --from=<stage> (passthrough of upstream artifacts) "
                        f"is allowed in mirror/* (arch.forge-mirror-image invariant; "
                        f"use a pre-builder tier if you need to add operator-defined files)."
                    )
                continue
            errors.append(
                f"{rel}:{i}: directive `{directive}` is not allowed in a mirror "
                f"image (arch.forge-mirror-image invariant — mirrors are zero-mod "
                f"passthroughs; allowed directives: {sorted(_MIRROR_ALLOWED_DIRECTIVES)}. "
                f"Use a pre-builder tier if you need to add behavior)."
            )

    # Rule 9 (FG-065): no RUN / COPY / ADD line pulls binaries from Docker Hub
    # or ghcr.io/library/ via HTTP. Those bypass FROM-level linting (FROM gets
    # Rules 2+3+7+8; HTTP pulls in RUN would silently sneak upstream bits in).
    # FROM + ARG lines are skipped — they have their own checks.
    for i, raw in enumerate(content.splitlines(), start=1):
        line = raw.split("#", 1)[0].rstrip()
        if not line:
            continue
        stripped = line.lstrip()
        if stripped.startswith(("FROM ", "ARG ", "LABEL ")):
            continue
        if _DOCKER_HUB_URL_RE.search(line):
            errors.append(
                f"{rel}:{i}: line references a Docker Hub URL "
                f"({line.strip()!r}). HTTP pulls from docker.io / "
                f"hub.docker.com / registry-1.docker.io / ghcr.io/library "
                f"in RUN/COPY/ADD lines bypass FROM-level linting. "
                f"Use a forge-rooted base (ARG <X>_REF=ghcr.io/bboortz/...) "
                f"or pull via a FROM stage + COPY --from= (the hc/syft helper "
                f"pattern) instead of a direct HTTP fetch."
            )

    return errors


def _check_rule_12_base_tier_invariants(local_images: set[str]) -> list[str]:
    """Rule 12 (reworked by FG-075): every `base/<name>` L3 image must be a
    well-formed Forge-signed public-API runtime foundation.

    FG-075 removed the earlier two sub-rules (final-stage FROM scratch +
    ≥1 forge-internal consumer) because the tier semantic widened:
      - base/* now covers BOTH scratch runtime foundations (e.g. base/
        python-scratch-trixie) AND slim runtime foundations (e.g. base/
        python-slim-trixie) — shape-agnostic.
      - base/* is the consumer-facing public API; external consumers
        (homelab, Beaconry) FROM it directly without a forge-internal
        consumer existing.

    What remains to check mechanically:
      (a) image.yaml exists AND declares `repo: base/<name>` explicitly
          (consistent with mirror/, pre-builder/, builder/, base/ nested
          repo convention; required for GHCR path resolution).
      (b) PROMISES.yaml exists (every forge image needs an authoritative
          contract — Rule 2 covers this globally, but we restate here so
          the base/ tier's contract requirement is visible).

    Decision context: docs/stories/FG-075-base-tier-public-api.md,
    docs/plan/FG-075-base-tier-public-api-plan.md § "Reworked Rule 12".
    """
    errors: list[str] = []
    base_images = {img for img in local_images if img.startswith("base/")}
    if not base_images:
        return errors

    for base in sorted(base_images):
        # (a) image.yaml declares explicit `repo: base/<name>`
        yml = IMAGES_DIR / base / "image.yaml"
        if not yml.is_file():
            errors.append(f"{base}: Rule 12 — missing image.yaml")
            continue
        try:
            txt = yml.read_text()
        except OSError:
            errors.append(f"{base}: Rule 12 — unreadable image.yaml")
            continue
        if not re.search(rf"^repo:\s+{re.escape(base)}\s*$", txt, re.MULTILINE):
            errors.append(
                f"{base}: Rule 12 — image.yaml must declare `repo: {base}` explicitly "
                f"(consistent with mirror/, pre-builder/, builder/ nested-repo convention)."
            )

        # (b) PROMISES.yaml exists (every base/* image publishes a contract)
        promises = IMAGES_DIR / base / "PROMISES.yaml"
        if not promises.is_file():
            errors.append(
                f"{base}: Rule 12 — missing PROMISES.yaml. Every base/* public-API "
                f"image publishes an authoritative contract (FG-010)."
            )

    return errors


def _check_rule_11_no_source_tier() -> list[str]:
    """FG-067 Rule 11: the retired L4.5 `source/` tier must never resurface.

    Decision context: docs/plan/tier-layering-model.md §O8 — the `source/`
    prefix was proposed to carry externally-sourced + from-source runtimes,
    then retired because that construction mechanism is a build-time
    detail of L4 runtimes. L4 absorbs from-source + externally-sourced
    runtimes directly; upstream source repos live at the external L0.1
    tier. Any new `images/source/` directory is almost certainly an
    author re-introducing the dead concept — fail lint so the choice is
    made explicit (flat L4 placement or L0.1 inventory entry).
    """
    errors: list[str] = []
    source_dir = IMAGES_DIR / "source"
    if source_dir.exists() and source_dir.is_dir():
        # Grab the offending leaf names for a helpful error.
        leaves = sorted(p.name for p in source_dir.iterdir() if p.is_dir())
        errors.append(
            f"images/source/ is a retired tier (Rule 11 / FG-067). "
            f"Found {len(leaves)} offending sub-dir(s): {leaves or '(empty)'}. "
            f"L4.5 `source/` was retired when from-source + externally-sourced "
            f"runtimes were absorbed into L4 (flat path) and upstream source "
            f"repos moved to the external L0.1 tier. Resolve by either: "
            f"(a) moving the image(s) to a flat `images/<name>/` path (L4 "
            f"runtime), OR (b) if this is an upstream source repo being "
            f"vendored, document it in the L0.1 inventory (see FG-068). "
            f"Full decision log: docs/plan/tier-layering-model.md §O8."
        )
    return errors


def _check_language_family_invariant(local_images: set[str]) -> list[str]:
    """FG-065 arch.language-family-image-pair invariant.

    Every `builder/<lang>-trixie/` image must have a sibling
    `pre-builder/<lang>-slim-trixie/` pre-builder. Enforces that new
    language families land as paired images (builder + pre-builder;
    builder dogfoods pre-builder).

    FG-070: pre-builder sibling canonical path is `pre-builder/<lang>-slim-trixie`.
    FG-071: builder canonical path is `builder/<lang>-trixie` (was flat
    `forge-builder-<lang>-trixie`).
    """
    errors: list[str] = []
    for img in sorted(local_images):
        m = re.match(r"^builder/([a-z0-9]+)-trixie$", img)
        if not m:
            continue
        lang = m.group(1)
        sibling = f"pre-builder/{lang}-slim-trixie"
        if sibling not in local_images:
            errors.append(
                f"images/{img}/: missing sibling pre-builder images/{sibling}/ "
                f"(FG-065 arch.language-family-image-pair invariant — "
                f"every builder/<lang>-trixie must have a pre-builder/"
                f"<lang>-slim-trixie pre-builder that it dogfoods)"
            )
    return errors


def _all_dockerfiles() -> list[Path]:
    # FG-066: walk flat + 1-nested so images/mirror/<name>/Dockerfile is found.
    out: list[Path] = []
    for p in sorted(IMAGES_DIR.iterdir()):
        if not p.is_dir():
            continue
        df = p / "Dockerfile"
        if df.is_file():
            out.append(df)
            continue
        for sub in sorted(p.iterdir()):
            if sub.is_dir() and (sub / "Dockerfile").is_file():
                out.append(sub / "Dockerfile")
    return out


def main() -> int:
    local_images = _local_images()
    all_errors: list[str] = []
    for df in _all_dockerfiles():
        all_errors.extend(_check_file(df, local_images))
    all_errors.extend(_check_language_family_invariant(local_images))
    all_errors.extend(_check_rule_11_no_source_tier())
    all_errors.extend(_check_rule_12_base_tier_invariants(local_images))

    if all_errors:
        sys.stderr.write("verify-dockerfile-conformance: FAIL\n")
        for e in all_errors:
            sys.stderr.write(f"  ✗ {e}\n")
        return 1

    n = len(_all_dockerfiles())
    print(f"verify-dockerfile-conformance: ok ({n} Dockerfile(s) conform to FG-064; FG-065 language-pair invariant + FG-066 mirror-tier invariant + FG-067 tier-prefix convention satisfied).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
