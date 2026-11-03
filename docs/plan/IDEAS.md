# Ideas backlog

Running list of ideas Claude + user have discussed but not yet promoted to stories. Append freely; prune when an idea becomes a story (link to the story file) or is explicitly rejected.

## Pending

- **python3.13 FROM scratch runtime** — the two-stage build in `memory/docker-standard.md`. Natural FG-002 after FG-001 pipeline is proven. Validates the ldd closure engineering as its own debuggable unit.
- **sid pin against a current real CVE** — natural FG-003. Picks a package where the fix is in `sid` but not yet backported to `trixie`; demonstrates the differentiator #1 end-to-end. Needs a shortlist of current candidates when scoped.
- **python3.13-builder (or -dev) variant** — slim + build-essential + headers, signed/scanned the same way, for use as a `FROM` in consumer builder stages. Mirrors Chainguard's `python` vs `python-dev` split.
- **Multi-arch (arm64)** — buildx + QEMU on GHA shared runners (or `ubuntu-22.04-arm`). Deferred because QEMU adds build-time variance that confuses pipeline debugging.
- **Multi-version matrix** — publish 3.12, 3.13, 3.14 in parallel from a single `images/python/` recipe via a GHA matrix. Adds the full tag stream (`python:3`, `python:latest`, `python:3.13-slim-trixie-YYYY-MM-DD`).
- **nginx-stable** — on the roadmap in README. Debian-based, FROM scratch runtime.
- **postgres-18** — on the roadmap in README. Debian-based, FROM scratch runtime.
- **Automatic PRs against dependent repos** — when a patched image is published, raise PRs updating consumers' pinned digests.
- **EU-hosted mirror (Frankfurt)** — data-sovereignty requirements.
- **BSI-aligned compliance report export (PDF)** — audit use.
- **Buildcache in registry** — `--cache-from=type=registry,ref=.../buildcache` + `--cache-to=mode=max`. Deferred until build time becomes painful.
- **Scan-regression gate** — PR fails if the scan introduces a new HIGH/CRITICAL vs. current `:latest`. Deferred to a dedicated story so the gate itself is testable.
- **Image-size gate** — PR fails if runtime image is > 10% larger than previous `:latest`. Deferred for the same reason.
- **Air-gapped verification path** — stored-key fallback for consumers who can't reach Rekor. V2 if a user asks.
