"""FG-068 — L0.1 upstream-source inventory.

Centralizes the list of external source repositories + release tarballs
that Forge builds consume at build time (never pulled as images). Every
`RUN git clone <URL>` and every `image.yaml source.git: <URL>` in the
repo MUST reference a key in `_UPSTREAM_SOURCES`; conversely every key
here MUST have at least one Forge consumer that actually uses it.

Enforced by `scripts/verify-source-inventory.py` (wired into `make test-fast`).

Why L0.1 is a first-class tier (vs. collapsing into L0):
  - Transport differs: L0 is `docker pull`, L0.1 is `git clone` / `curl .tar.xz`.
  - CVE tracking differs: L0 is OS-package DB (dpkg/apk); L0.1 is the derived
    L4 image's Go-module / npm / PyPI SBOM.
  - Pinning differs: L0 uses image digests; L0.1 uses git refs + tarball SHA256.
  - Supply-chain surface differs: L0 is Docker Hub + GHCR; L0.1 is GitHub + tarball hosts.

See `docs/plan/tier-layering-model.md` §3 "L0.1 — Upstream sources" for the
full semantic test + rationale.
"""

from __future__ import annotations

# URL → list of forge image-dir names (`images/<name>/`) that consume this source.
# URLs are canonicalized without trailing slash + without `.git` suffix for
# stable keys; the verifier strips both forms at compare time.
_UPSTREAM_SOURCES: dict[str, list[str]] = {
    # FG-012 externally-sourced (image.yaml source.git: ... — the whole
    # upstream Dockerfile is cloned + built).
    "github.com/bboortz/beaconry": [
        "beaconry-hub",
        "beaconry-scout",
        "beaconry-telegram-mock",
    ],

    # From-Go-source in builder stage (RUN git clone + go build).
    "github.com/google/cadvisor": ["cadvisor-slim-trixie"],
    "github.com/prometheus/prometheus": ["prometheus-scratch-trixie"],
    "github.com/prometheus/alertmanager": ["alertmanager-scratch-trixie"],
    "github.com/prometheus/node_exporter": ["node-exporter-scratch-trixie"],
    "github.com/prometheus-community/ipmi_exporter": [
        "ipmi-exporter-scratch-trixie",
        "ipmi-exporter-slim-trixie",
    ],
    "github.com/tianon/gosu": ["postgres-slim-trixie"],

    # From-Node-source in builder stage.
    "github.com/louislam/uptime-kuma": ["uptime-kuma-slim-trixie"],

    # Release-tarball downloaded via curl + resolved via GitHub Releases API.
    "github.com/actions/runner": ["github-runner-noble"],

    # External tarball host (not GitHub; committed SHA256 for provenance).
    "ziglang.org/download": ["zig-slim-trixie"],
}


def canonical_url(url: str) -> str:
    """Strip trailing slash + `.git` suffix + leading `https://` so keys are
    stable regardless of how the URL appears in the Dockerfile / image.yaml.

    Examples:
      https://github.com/google/cadvisor.git/ → github.com/google/cadvisor
      https://github.com/bboortz/beaconry     → github.com/bboortz/beaconry
    """
    u = url.strip()
    for prefix in ("https://", "http://"):
        if u.startswith(prefix):
            u = u[len(prefix):]
            break
    if u.endswith("/"):
        u = u[:-1]
    if u.endswith(".git"):
        u = u[:-4]
    # Normalize ziglang.org/download/<ver>/zig-*.tar.xz → ziglang.org/download
    # (the version is part of the ARG, not the inventory key — we track the host
    # + path prefix, not the exact tarball).
    if u.startswith("ziglang.org/download"):
        u = "ziglang.org/download"
    return u
