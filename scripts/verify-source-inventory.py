#!/usr/bin/env python3
"""FG-068 — verify L0.1 upstream-source inventory stays in sync with code.

Two-way check against `scripts/_upstream_sources.py`:

  (a) FORWARD — every upstream-source URL referenced in Dockerfiles or
      image.yaml source.git blocks must have an inventory entry AND the
      referencing image must be a declared consumer.

  (b) REVERSE — every entry in `_UPSTREAM_SOURCES` must be referenced in at
      least one of its declared consumers' Dockerfile or image.yaml. Stale
      inventory entries are a fail.

URL recognition:
  - `https://github.com/<org>/<repo>` + optional `.git` + optional path tail →
    normalized to `github.com/<org>/<repo>`.
  - `https://ziglang.org/download/...` → normalized to `ziglang.org/download`.

Explicit skip list (not L0.1 build inputs):
  - `github.com/bboortz/forge` — Forge's own self-reference in OCI labels.
  - `github.com/hadolint/hadolint` — CI tool install path, not a forge image
    build input.
  - `github.com/anchore/grype`, `github.com/anchore/syft` — scanner/sbom CLI
    install paths used in CI; the syft BINARY lives at `mirror/syft` (L0.5),
    not L0.1.
  - `github.com/sigstore/cosign` — signing CLI install path.

Exit codes:
  0 — in sync
  1 — drift detected (details on stderr)
  2 — IO / internal error
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = REPO_ROOT / "images"
SCRIPTS_DIR = REPO_ROOT / "scripts"

sys.path.insert(0, str(SCRIPTS_DIR))
from _upstream_sources import _UPSTREAM_SOURCES, canonical_url  # noqa: E402

# Non-L0.1 URLs that legitimately appear in Dockerfiles (labels, CI tool
# install paths that run on the GHA runner, not inside a forge image build).
_SKIP = {
    "github.com/bboortz/forge",
    "github.com/hadolint/hadolint",
    "github.com/anchore/grype",
    "github.com/anchore/syft",
    "github.com/sigstore/cosign",
}

_GITHUB_URL_RE = re.compile(r"https?://github\.com/([a-zA-Z0-9][a-zA-Z0-9._-]*)/([a-zA-Z0-9][a-zA-Z0-9._-]*)")
_ZIG_URL_RE = re.compile(r"https?://ziglang\.org/download/[^\s'\"\\]+")


def _parse_yaml_source_git(image_yaml: Path) -> str | None:
    """Minimal YAML-ish parser for `source.git:` — avoids pulling in PyYAML."""
    try:
        txt = image_yaml.read_text()
    except OSError:
        return None
    in_source = False
    for raw in txt.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith("source:"):
            in_source = True
            continue
        if in_source:
            if not line.startswith((" ", "\t")):
                in_source = False
                continue
            m = re.match(r"\s+git:\s*(.+)", line)
            if m:
                return m.group(1).strip().strip('"').strip("'")
    return None


def _collect_urls_in_text(text: str) -> list[str]:
    """Find every github.com/<org>/<repo> reference (stripping trailing .git /
    URL path tail) + every ziglang.org/download URL. Returns canonicalized
    inventory keys."""
    found: list[str] = []
    for m in _GITHUB_URL_RE.finditer(text):
        org, repo = m.group(1), m.group(2)
        # Strip trailing .git from repo (common in clone URLs).
        if repo.endswith(".git"):
            repo = repo[:-4]
        found.append(f"github.com/{org}/{repo}")
    for m in _ZIG_URL_RE.finditer(text):
        found.append("ziglang.org/download")
    return found


def _walk_image_dir(image_dir: Path) -> list[tuple[str, str]]:
    """Return list of (canonical_url, kind) pairs referenced by this image."""
    refs: list[tuple[str, str]] = []

    image_yaml = image_dir / "image.yaml"
    if image_yaml.is_file():
        src_git = _parse_yaml_source_git(image_yaml)
        if src_git:
            refs.append((canonical_url(src_git), "image.yaml source.git"))

    dockerfile = image_dir / "Dockerfile"
    if dockerfile.is_file():
        try:
            df = dockerfile.read_text()
        except OSError:
            return refs
        for url in _collect_urls_in_text(df):
            refs.append((url, "Dockerfile URL"))

    return refs


def _image_dirs() -> list[Path]:
    out: list[Path] = []
    for p in IMAGES_DIR.iterdir():
        if not p.is_dir():
            continue
        if (p / "image.yaml").is_file() or (p / "Dockerfile").is_file():
            out.append(p)
            continue
        for sub in p.iterdir():
            if sub.is_dir() and ((sub / "image.yaml").is_file() or (sub / "Dockerfile").is_file()):
                out.append(sub)
    return out


def main() -> int:
    errors: list[str] = []

    # Build actual-usage map: canonical_url → set of consumer image names.
    actual: dict[str, set[str]] = {}
    for d in _image_dirs():
        consumer = d.relative_to(IMAGES_DIR).as_posix()
        for url, _kind in _walk_image_dir(d):
            if url in _SKIP:
                continue
            actual.setdefault(url, set()).add(consumer)

    # (a) FORWARD — every actual URL must be in inventory + consumer must be declared.
    for url in sorted(actual):
        if url not in _UPSTREAM_SOURCES:
            offenders = ", ".join(sorted(actual[url]))
            errors.append(
                f"source reference not in inventory: '{url}' — used by {offenders}. "
                f"Add '{url}' to scripts/_upstream_sources.py:_UPSTREAM_SOURCES "
                f"(or to _SKIP in scripts/verify-source-inventory.py if this is a "
                f"non-L0.1 helper URL)."
            )
            continue
        declared = set(_UPSTREAM_SOURCES[url])
        undeclared = actual[url] - declared
        for consumer in sorted(undeclared):
            errors.append(
                f"consumer drift: image '{consumer}' references '{url}' but is NOT "
                f"declared in _UPSTREAM_SOURCES[{url!r}]. Either add '{consumer}' to "
                f"that list or stop referencing the URL."
            )

    # (b) REVERSE — every inventory entry must have ≥1 actual reference from a declared consumer.
    for url, declared_consumers in sorted(_UPSTREAM_SOURCES.items()):
        actual_consumers = actual.get(url, set())
        unused = [c for c in declared_consumers if c not in actual_consumers]
        if unused:
            errors.append(
                f"inventory drift: '{url}' lists consumer(s) {unused} but none of those "
                f"images actually reference the URL. Remove stale entries or restore the "
                f"reference."
            )

    if errors:
        sys.stderr.write("verify-source-inventory: FAIL\n")
        for e in errors:
            sys.stderr.write(f"  ✗ {e}\n")
        return 1

    n_sources = len(_UPSTREAM_SOURCES)
    n_consumers = sum(len(v) for v in _UPSTREAM_SOURCES.values())
    print(f"verify-source-inventory: ok ({n_sources} L0.1 source(s), {n_consumers} consumer declaration(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
