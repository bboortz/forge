# Ideas backlog

Running list of ideas Claude + user have discussed but not yet promoted to stories. Append freely; prune when an idea becomes a story (link to the story file) or is explicitly rejected.

## Scoped — decisions locked, waiting to land

- **FG-005 — `scratch-base-trixie`: shared signed foundation for every Forge scratch image.** Produces `ghcr.io/bboortz/scratch-base-trixie:latest` (+ `:0.1` / etc.) containing the glibc + NSS + CA-bundle + zoneinfo + minimal `/etc` closure. Language-specific libs (sqlite3, pcre, icu, …) stay in each language image.
  - **Derivative pattern**: `FROM scratch` + `COPY --from=ghcr.io/bboortz/scratch-base-trixie:latest / /` — preserves literal "FROM scratch" semantics for the differentiator pitch.
  - **Tests**: file-contents inspection via `docker save | tar tf` (scratch has no exec); no sidecar plumbing. Lives under `images/scratch-base-trixie/tests/smoke_contents_*.sh`.
  - **Versioning**: semantic (`0.1` → `0.2` on surface change), manual bumps. `:latest` moves with every rebuild.
  - **Differentiators doc**: add a short paragraph explaining the baseline layer so "FROM scratch" stays honest.
  - **Build order**: CI matrix runs baseline before derivatives. Local dev: `make build IMAGE_DIR=scratch-base-trixie` first.
  - **Refactors**: `python-scratch-trixie/Dockerfile` drops the glibc/NSS/CA/zoneinfo COPYs and `COPY --from=` the baseline instead. Existing FG-003 smoke suite is the oracle.

## Pending

- **sid pin against a current real CVE** — natural follow-up after FG-005/006/007. Picks a package where the fix is in `sid` but not yet backported to `trixie`; demonstrates the differentiator #1 end-to-end. Needs a shortlist of current candidates when scoped.
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
- **Cosign v3 migration** (review by **2026-11-17**) — currently pinned to v2.4.3 everywhere because v3 stores sigs as OCI 1.1 referrers (`sha256-<digest>` without `.sig`) that legacy verifiers miss, and dropped `--tlog-upload=false` which `make sign-local` depends on. Evaluate: upgrade everywhere + rewrite sign-local around a tlog-less signing-config, or renew the v2 pin. See `memory/supply-chain.md` review note.
- ~~**Stamp-based rebuild skip** (FG-017 Part D)~~ — promoted to [FG-023 smart-rebuild-skip](../stories/FG-023-smart-rebuild-skip.md).
- ~~**CI PR gate uses smart-check** (FG-017 follow-up)~~ — shipped as [FG-018 ci-uses-smart-check](../stories/FG-018-ci-uses-smart-check.md).
- **`build.yml` workflow_dispatch image filter** — current `build.yml` rebuilds all 17 images on every manual dispatch (~15 min floor) even when only one image needs republishing (observed twice this week: FG-039, FG-040). Proposed: add `workflow_dispatch.inputs.images` ("all" / dir name / comma list / glob), filter the `discover` job's matrix output based on the input. Nightly cron keeps default "all"; operator runs `gh workflow run build.yml -f images=prometheus-scratch-trixie` for post-fix republishes. One file, ~30 lines of change. Alternative splits (3 pipelines by tier or by cluster) rejected — they don't solve the "rebuild one image" case, add cross-workflow trigger brittleness, and require per-image maintainer decisions. See conversation 2026-11-09.
- **Scratch-image on-disk asset audit** — FG-039 + FG-040 both caught the same class of bug (Debian ships compile-time-hardcoded paths under `/usr/share/<pkg>/` and/or symlinks into `/usr/share/javascript/`; `cp -r` of the obvious dir misses them). Audit every scratch image (nginx, postgres, redis, mosquitto, node-exporter, prometheus, alertmanager) for similar compile-time-hardcoded paths. **Low-cost preventive**: one-time inspection of `apt-file list <pkg>` outputs for `/usr/share/*`, `/var/lib/*`, `/usr/lib/*/plugins/*`, etc. that aren't being COPY'd into overlays. Might surface 0 issues (we got lucky), might surface 2-3 FG-sized fixes before consumers hit them.
