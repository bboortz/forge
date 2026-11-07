#!/usr/bin/env python3
# Forge contract verifier — lints the image-to-image dependency graph
# declared in images/<name>/PROMISES.yaml + images/<name>/EXPECTATIONS.yaml.
#
# Exit codes:
#   0  — graph is consistent
#   1  — at least one violation
#   2  — environmental problem (pyyaml missing, repo layout broken)

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "verify-contracts: python3-yaml missing. Install via your package "
        "manager (apt install python3-yaml / pip install pyyaml) and retry.\n"
    )
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"
CAPABILITIES_FILE = REPO_ROOT / "docs" / "CAPABILITIES.md"
SPEC_VERSION = 1

# e.g. ">=0.2", ">0.1", "0.2", "~0.2"
VERSION_CONSTRAINT = re.compile(r"^(>=|<=|>|<|~|=)?\s*(\d+)\.(\d+)(?:\.(\d+))?$")


@dataclass
class Promise:
    id: str
    description: str
    caps: list[str] = field(default_factory=list)
    tests: list[str] = field(default_factory=list)
    inverse: bool = False
    source_file: Path = Path()


@dataclass
class ImagePromises:
    image: str
    version: str
    spec_version: int
    promises: dict[str, Promise]
    source_file: Path


@dataclass
class Expectation:
    promise_id: str
    reason: str
    preflight: list[str]
    source_file: Path
    dep_image: str


@dataclass
class ImageExpectations:
    image: str
    spec_version: int
    dependencies: list[dict]  # raw list
    source_file: Path


def err(errors: list[str], msg: str) -> None:
    errors.append(msg)


def parse_version(v: str) -> tuple[int, int, int] | None:
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", v)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))


def satisfies(actual: str, constraint: str) -> bool | None:
    # Returns None when the constraint syntax itself is invalid.
    m = VERSION_CONSTRAINT.match(constraint)
    a = parse_version(actual)
    if not m or a is None:
        return None
    op = m.group(1) or "="
    want = (int(m.group(2)), int(m.group(3)), int(m.group(4) or 0))
    if op == "=":
        return a == want
    if op == ">=":
        return a >= want
    if op == ">":
        return a > want
    if op == "<=":
        return a <= want
    if op == "<":
        return a < want
    if op == "~":
        # same major.minor, any patch
        return a[0] == want[0] and a[1] == want[1]
    return None


def load_promises(path: Path, errors: list[str]) -> ImagePromises | None:
    with path.open() as f:
        try:
            data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            err(errors, f"{path}: invalid YAML — {e}")
            return None
    if not isinstance(data, dict):
        err(errors, f"{path}: top-level must be a mapping")
        return None
    spec = data.get("spec_version")
    if spec != SPEC_VERSION:
        err(errors, f"{path}: spec_version must be {SPEC_VERSION} (got {spec!r})")
        return None
    image = data.get("image")
    expected_image = path.parent.name
    if image != expected_image:
        err(errors, f"{path}: image: field is {image!r}, expected {expected_image!r} (dir name)")
    version = data.get("version")
    if not isinstance(version, str) or not parse_version(version):
        err(errors, f"{path}: version: must be a semver string like '0.2' or '1.0.0' (got {version!r})")
        version = "0.0.0"
    raw_promises = data.get("promises")
    if not isinstance(raw_promises, list):
        err(errors, f"{path}: promises: must be a list (got {type(raw_promises).__name__})")
        return None
    promises: dict[str, Promise] = {}
    for idx, raw in enumerate(raw_promises):
        if not isinstance(raw, dict):
            err(errors, f"{path}: promises[{idx}] must be a mapping")
            continue
        pid = raw.get("id")
        if not isinstance(pid, str) or not pid:
            err(errors, f"{path}: promises[{idx}] missing id")
            continue
        if pid in promises:
            err(errors, f"{path}: promises[{idx}] duplicate id {pid!r}")
            continue
        desc = raw.get("description")
        if not isinstance(desc, str) or not desc:
            err(errors, f"{path}: promise {pid!r} missing description")
            desc = ""
        caps = raw.get("caps", [])
        if not isinstance(caps, list) or not all(isinstance(c, str) for c in caps):
            err(errors, f"{path}: promise {pid!r} caps must be a list of strings")
            caps = []
        tests = raw.get("tests", [])
        if not isinstance(tests, list) or not tests or not all(isinstance(t, str) for t in tests):
            err(errors, f"{path}: promise {pid!r} tests must be a non-empty list of path strings")
            tests = []
        inverse = bool(raw.get("inverse", False))
        # FG-019: validate absence.os-cves waivers (optional list of
        # {cve, reason, until} per promise). Only meaningful on the
        # inverse absence.os-cves promise; we validate shape wherever present.
        raw_waivers = raw.get("waivers")
        if raw_waivers is not None:
            if not isinstance(raw_waivers, list):
                err(errors, f"{path}: promise {pid!r} waivers must be a list")
            else:
                import datetime as _dt
                today = _dt.date.today()
                seen_cves: set[str] = set()
                for widx, w in enumerate(raw_waivers):
                    if not isinstance(w, dict):
                        err(errors, f"{path}: promise {pid!r} waivers[{widx}] must be a mapping")
                        continue
                    wcve = w.get("cve")
                    wreason = w.get("reason")
                    wuntil = w.get("until")
                    if not isinstance(wcve, str) or not wcve:
                        err(errors, f"{path}: promise {pid!r} waivers[{widx}] missing 'cve'")
                        continue
                    if wcve in seen_cves:
                        err(errors, f"{path}: promise {pid!r} duplicate waiver for {wcve}")
                        continue
                    seen_cves.add(wcve)
                    if not isinstance(wreason, str) or not wreason:
                        err(errors, f"{path}: promise {pid!r} waiver {wcve!r} missing 'reason'")
                    if not isinstance(wuntil, str):
                        err(errors, f"{path}: promise {pid!r} waiver {wcve!r} missing 'until' (ISO date)")
                        continue
                    try:
                        wdate = _dt.date.fromisoformat(wuntil)
                    except ValueError:
                        err(errors, f"{path}: promise {pid!r} waiver {wcve!r} has invalid date {wuntil!r} (want ISO YYYY-MM-DD)")
                        continue
                    if wdate < today:
                        err(errors, f"{path}: promise {pid!r} waiver {wcve!r} expired {wdate} — renew or fix the CVE")
        promises[pid] = Promise(
            id=pid,
            description=desc,
            caps=list(caps),
            tests=list(tests),
            inverse=inverse,
            source_file=path,
        )
    return ImagePromises(
        image=str(image or expected_image),
        version=str(version),
        spec_version=spec,
        promises=promises,
        source_file=path,
    )


def load_expectations(path: Path, errors: list[str]) -> ImageExpectations | None:
    with path.open() as f:
        try:
            data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            err(errors, f"{path}: invalid YAML — {e}")
            return None
    if not isinstance(data, dict):
        err(errors, f"{path}: top-level must be a mapping")
        return None
    spec = data.get("spec_version")
    if spec != SPEC_VERSION:
        err(errors, f"{path}: spec_version must be {SPEC_VERSION} (got {spec!r})")
        return None
    image = data.get("image")
    expected_image = path.parent.name
    if image != expected_image:
        err(errors, f"{path}: image: field is {image!r}, expected {expected_image!r}")
    deps = data.get("dependencies")
    if not isinstance(deps, list) or not deps:
        err(errors, f"{path}: dependencies: must be a non-empty list")
        deps = []
    return ImageExpectations(
        image=str(image or expected_image),
        spec_version=spec,
        dependencies=list(deps),
        source_file=path,
    )


def load_cap_ids(errors: list[str]) -> set[str]:
    """Extract CAP ids from docs/CAPABILITIES.md. Each entry is a '### <id>' heading."""
    if not CAPABILITIES_FILE.exists():
        err(errors, f"{CAPABILITIES_FILE}: missing")
        return set()
    caps: set[str] = set()
    for line in CAPABILITIES_FILE.read_text().splitlines():
        m = re.match(r"^###\s+(\S+)\s*$", line)
        if m:
            caps.add(m.group(1))
    return caps


def resolve_test_path(raw: str) -> Path:
    # Paths in YAML are repo-root-relative.
    return (REPO_ROOT / raw).resolve()


def discover_smoke_tests() -> set[Path]:
    """Every executable images/*/tests/*.sh — the set picked up by test-images."""
    out: set[Path] = set()
    for p in IMAGES_DIR.glob("*/tests/*.sh"):
        if p.is_file() and os.access(p, os.X_OK):
            out.add(p.resolve())
    return out


def main() -> int:
    if not IMAGES_DIR.is_dir():
        sys.stderr.write(f"verify-contracts: {IMAGES_DIR} missing — not at repo root?\n")
        return 2

    errors: list[str] = []

    # 1. Load every PROMISES.yaml — one per image.
    promise_files = sorted(IMAGES_DIR.glob("*/PROMISES.yaml"))
    image_dirs = sorted(p for p in IMAGES_DIR.iterdir() if p.is_dir())
    image_names = {p.name for p in image_dirs}
    images_with_promises: dict[str, ImagePromises] = {}
    for pf in promise_files:
        ip = load_promises(pf, errors)
        if ip is None:
            continue
        images_with_promises[pf.parent.name] = ip

    missing = image_names - set(images_with_promises)
    for m in sorted(missing):
        err(errors, f"images/{m}/PROMISES.yaml: missing (every image must declare its promises)")

    # 2. Cross-check CAP references.
    cap_ids = load_cap_ids(errors)
    for img, ip in images_with_promises.items():
        for promise in ip.promises.values():
            for cap in promise.caps:
                if cap not in cap_ids:
                    err(errors, f"{ip.source_file}: promise {promise.id!r} references cap {cap!r} that is not declared in docs/CAPABILITIES.md")

    # 3. Cross-check test file existence + executability.
    all_smokes = discover_smoke_tests()
    for ip in images_with_promises.values():
        for promise in ip.promises.values():
            for t in promise.tests:
                tp = resolve_test_path(t)
                if not tp.exists():
                    err(errors, f"{ip.source_file}: promise {promise.id!r} references missing test {t}")
                elif not os.access(tp, os.X_OK):
                    err(errors, f"{ip.source_file}: promise {promise.id!r} references non-executable test {t}")

    # 4. Load every EXPECTATIONS.yaml — only on images that depend on another Forge image.
    expectation_files = sorted(IMAGES_DIR.glob("*/EXPECTATIONS.yaml"))
    images_with_expectations: dict[str, ImageExpectations] = {}
    for ef in expectation_files:
        ie = load_expectations(ef, errors)
        if ie is None:
            continue
        images_with_expectations[ef.parent.name] = ie

    # Images that have depends_on: in image.yaml but no EXPECTATIONS.yaml are errors.
    for d in image_dirs:
        iy = d / "image.yaml"
        if not iy.exists():
            continue
        has_deps = False
        in_deps = False
        for line in iy.read_text().splitlines():
            if line.startswith("depends_on:"):
                in_deps = True
                continue
            if in_deps and line and not line[0].isspace():
                in_deps = False
            if in_deps and line.strip().startswith("-"):
                has_deps = True
                break
        if has_deps and d.name not in images_with_expectations:
            err(errors, f"images/{d.name}/EXPECTATIONS.yaml: missing but image.yaml declares depends_on")

    # 5. Validate every expectation against its dependency's promises.
    for img, ie in images_with_expectations.items():
        for dep_idx, dep in enumerate(ie.dependencies):
            if not isinstance(dep, dict):
                err(errors, f"{ie.source_file}: dependencies[{dep_idx}] must be a mapping")
                continue
            dep_image = dep.get("image")
            if not isinstance(dep_image, str):
                err(errors, f"{ie.source_file}: dependencies[{dep_idx}] missing image: field")
                continue
            if dep_image not in images_with_promises:
                err(errors, f"{ie.source_file}: dependency image {dep_image!r} has no PROMISES.yaml")
                continue
            dep_ip = images_with_promises[dep_image]
            constraint = dep.get("version")
            if not isinstance(constraint, str):
                err(errors, f"{ie.source_file}: dependencies[{dep_idx}] missing version: constraint")
            else:
                sat = satisfies(dep_ip.version, constraint)
                if sat is None:
                    err(errors, f"{ie.source_file}: invalid version constraint {constraint!r} on dependency {dep_image!r}")
                elif not sat:
                    err(errors, f"{ie.source_file}: dependency {dep_image!r} version {dep_ip.version} does not satisfy constraint {constraint!r}")
            exps = dep.get("expectations")
            if not isinstance(exps, list) or not exps:
                err(errors, f"{ie.source_file}: dependency {dep_image!r} needs a non-empty expectations: list")
                continue
            for e_idx, e in enumerate(exps):
                if not isinstance(e, dict):
                    err(errors, f"{ie.source_file}: dependency {dep_image!r} expectations[{e_idx}] must be a mapping")
                    continue
                pid = e.get("promise")
                reason = e.get("reason")
                preflight = e.get("preflight")
                if not isinstance(pid, str):
                    err(errors, f"{ie.source_file}: expectations[{e_idx}] on {dep_image!r} missing promise: id")
                    continue
                if pid not in dep_ip.promises:
                    err(errors, f"{ie.source_file}: {img} expects promise {pid!r} but {dep_image} does not declare it (see {dep_ip.source_file})")
                if not isinstance(reason, str) or not reason:
                    err(errors, f"{ie.source_file}: expectation on {pid!r} missing reason:")
                if not isinstance(preflight, list) or not preflight or not all(isinstance(p, str) for p in preflight):
                    err(errors, f"{ie.source_file}: expectation on {pid!r} preflight: must be non-empty list of test paths")
                    continue
                for p in preflight:
                    pp = resolve_test_path(p)
                    if not pp.exists():
                        err(errors, f"{ie.source_file}: expectation on {pid!r} references missing preflight {p}")
                        continue
                    if not os.access(pp, os.X_OK):
                        err(errors, f"{ie.source_file}: expectation on {pid!r} references non-executable preflight {p}")
                        continue
                    # Preflight must live under images/*/tests/ so test-images picks it up.
                    try:
                        rel = pp.relative_to(IMAGES_DIR)
                    except ValueError:
                        err(errors, f"{ie.source_file}: preflight {p} must live under images/*/tests/ (so make test-images runs it)")
                        continue
                    parts = rel.parts
                    if len(parts) < 3 or parts[1] != "tests":
                        err(errors, f"{ie.source_file}: preflight {p} must live under images/*/tests/")

    if errors:
        sys.stderr.write("verify-contracts: FAIL ({} violation(s))\n".format(len(errors)))
        for e in errors:
            sys.stderr.write(f"  ✗ {e}\n")
        return 1

    n_promises = sum(len(ip.promises) for ip in images_with_promises.values())
    n_expectations = sum(
        sum(len(dep.get("expectations", [])) for dep in ie.dependencies)
        for ie in images_with_expectations.values()
    )
    _unused_smokes = all_smokes  # reserved for a future "orphaned smoke" lint
    print(
        f"verify-contracts: ok "
        f"({len(images_with_promises)} image(s), {n_promises} promise(s), "
        f"{len(images_with_expectations)} dependent image(s), {n_expectations} expectation(s))"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
