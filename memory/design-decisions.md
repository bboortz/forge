*Locked design decisions for Forge. Source: README + initial scoping.*

## Base distribution — Debian trixie (not Wolfi, not Alpine)

Forge targets workloads that need glibc compatibility: existing `.so` assumptions, Debian packaging conventions, regulated environments requiring a Debian CVE tracking baseline (BSI, Common Criteria). Chainguard already serves the Wolfi/musl niche well — Forge does not compete there.

Consequence: our scanner coverage is NVD + Debian Security Tracker. Not Wolfi advisories, not Alpine SecDB.

### Exception — Ubuntu (FG-051, 2026-11-14)

Debian trixie remains the default. Ubuntu is accepted **case-by-case** for specific images with Ubuntu-specific library requirements that trixie doesn't satisfy. First precedent:

- **`ubuntu-slim-noble` (24.04 "noble", LTS until April 2029)** — Forge pre-builder FROMing `ubuntu:24.04`. Rationale: the GitHub Actions self-hosted runner (`actions/runner`) embeds a .NET 6 runtime whose `installdependencies.sh` only tries `libicu70-72`. Debian trixie ships `libicu76`; Ubuntu 24.04 ships `libicu74`. Picking Ubuntu for the runner image is the lowest-friction path vs patching upstream's installer or chasing a sid pin that would still rename on each libicu bump.

**Policy for future Ubuntu additions**:
- Default is still Debian trixie. Ubuntu is reached for only when a specific library or runtime pin makes it necessary, with the story documenting the reason.
- Ubuntu scanner coverage is NVD + Ubuntu CVE tracker (grype's `ubuntu` matcher). Our scan-regression gate already handles both ecosystems.
- Ubuntu images follow the same chain-depth + single-upstream-consumer invariants (FG-042): a single Forge pre-builder per family (`ubuntu-slim-noble`), downstream Ubuntu-needing images FROM the pre-builder, not `ubuntu:24.04` directly. Enforced by `scripts/verify-no-upstream-drift.sh`.
- One LTS release at a time. When Ubuntu 26.04 LTS ships (April 2026 cycle — tracked via a future story), we rev the pre-builder; no overlap window unless a consumer explicitly needs it.

### Exception — Debian sid (FG-058, 2026-11-15)

Debian trixie remains the default. Debian sid is accepted **case-by-case** when a specific CVE or feature requires it. First precedent:

- **`debian-slim-sid` pre-builder** — `FROM debian:sid-slim`. Zero consumers today; sits in the publish-pre-builders CI tier as infrastructure. Rationale: trixie occasionally ships CVE-exposed legacy-ABI packages that Debian explicitly won't fix (the trigger for FG-058 was libxml2 2.9.14's `<no-dsa>` UAF; sid preserves the same vulnerable `.so.2` ABI by design so a sid pin didn't help *in that specific case*). But future CVEs on packages where sid DOES ship a `.so.2`-compatible fix (curl, openssl rolling point releases, etc.) can land in a 30-min FG by consuming this pre-builder.

**Policy for `debian-slim-sid` consumption**:

- Default is still Debian trixie. Reach for sid only when a specific trixie package is stuck unfixed AND sid's version is ABI-compatible with the downstream consumer.
- Document the reason in the consumer image's story + reference FG-058's pre-builder.
- Rolling-release means scan-baseline.json drifts more than trixie's. Accept nonzero CRITICALs; daily cron re-resolves.
- Chain-depth invariant (FG-042) still applies: downstream images FROM `debian-slim-sid`, not `debian:sid-slim` directly. Enforced by `scripts/verify-no-upstream-drift.sh` (`_EXPECTED=4`; `debian:sid-slim` added to `_UPSTREAM_ANCHORS`).

## sid pinning — faster than waiting for backports

When a CVE fix lands in Debian `sid` but has not yet been backported to `trixie`, Forge pulls that specific package from `sid` while the rest of the image stays on `trixie`. Mechanism: `/etc/apt/preferences.d/` pin files committed in `images/<name>/sid-pins/`, enabled during the builder stage.

Policy:
- Pin **only** the vulnerable package, never the whole base
- Every active pin references the CVE it addresses (comment in the pin file)
- Remove the pin as soon as the fix is backported to `trixie` — pins decay silently otherwise
- A pin that references a CVE older than 60 days is a review signal: either the pin is now unnecessary (backport landed) or the pin itself has been superseded by a newer sid version

## Daily rebuild cadence — 03:00 UTC

GitHub Actions cron `0 3 * * *` rebuilds every image with `docker buildx build --pull`. Rationale: `--pull` guarantees the FROM reference is re-resolved against the registry, so freshly released base layers propagate within 24h without manual intervention.

Why 03:00 UTC: lowest contention window on GHA shared runners, well after Debian's typical daily FTP sync (~01:00 UTC).

## Two-stage build, `FROM scratch` runtime

Stage 1 (builder) is a conventional `python:3.13-slim-trixie` with `apt`, `curl`, `pip` — anything we need to assemble artifacts.

Stage 2 (runtime) is `FROM scratch`. We `COPY` only:
- Python interpreter + stdlib
- libc, libssl, libm, ld-linux (and whatever else `ldd $(which python3)` enumerates)
- Statically linked tool binaries if any
- Application dependencies installed into `/install`

Consequences we want:
- No shell → no `docker exec` for debugging, but also no shell-based CVE class
- No package manager → no persistent install surface
- **No dpkg database** → grype finds no OS-level CVE candidates in the runtime image because there is no OS package metadata to scan. The only matches are the PyPI packages the consumer installed. This is the point: every grype finding against a Forge image is actionable by the consumer, not noise about a Debian package the consumer never asked for.

The `-slim` variant trades this away: we publish `python:3.13-slim-trixie` after `apt upgrade` with the same scan+sign treatment, for operators who need a shell.

## Attestation triple — grype + syft + cosign

Every published digest ships with three artifacts attached as OCI annotations:

| Artifact | Tool | Format |
|---|---|---|
| CVE scan result | grype | JSON |
| SBOM | syft | CycloneDX JSON |
| Signature | cosign | keyless (GHA OIDC) |

The signature covers the digest; the scan + SBOM are additional attestations.

Verification identity: `--certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml`, `--certificate-oidc-issuer https://token.actions.githubusercontent.com`. The identity string is tied to the workflow file path — if we move the workflow, we break every downstream verify. Treat the path as a stable public interface.

## Image set V1

| Image | Status | Shape |
|---|---|---|
| `python3.13` | ship | trixie builder → `FROM scratch` runtime |
| `python3.13-slim` | ship | published as-is after `apt upgrade` |
| `nginx:stable` | roadmap | Debian-based, `FROM scratch` runtime |
| `postgres:18` | roadmap | Debian-based, `FROM scratch` runtime |

Roadmap also tracks: automatic PRs against dependent repos, EU-hosted mirror (Frankfurt), BSI-aligned compliance report export.

## Repo naming — one GHCR repo per variant

*Locked 2026-11-03 (FG-004). Supersedes the earlier "single `python` repo with variant in the tag" scheme shipped under FG-001.*

Each image variant publishes to its **own GHCR repo**, named identically to the `images/<dir>/` directory. The variant lives in the repo name; the tag carries the version (and optionally the architecture).

- `ghcr.io/bboortz/python-slim-trixie:3.13`
- `ghcr.io/bboortz/python-scratch-trixie:3.13`

Per publish, each variant pushes a 4-tag family pointing at the same digest:

- `:<version>` (primary; manifest list once arm64 lands)
- `:<version>-amd64` (arch-explicit; stays a direct arch digest when arm64 lands)
- `:latest` (floating)
- `:latest-amd64` (floating + arch-explicit)

Arch suffix is `amd64` / `arm64` — matches Docker's `TARGETARCH` value, matches upstream convention. No `linux-` prefix.

Directory-name == repo-name is the single source of truth. `image.yaml` does **not** carry a `repo:` field; scripts derive repo from `basename` of the image dir. If a future image ever needs a non-matching repo name, `image.yaml` can carry an explicit `repo:` override — but prefer renaming the directory instead.

## `:latest` is published — digests are the contract

`:latest` moves daily, so consumers who want reproducibility must pin a specific version tag (`:3.13`) or a digest (`@sha256:...`). We publish `:latest` for the convention-matching consumer who wants "whatever is current" — the README calls out the silent-roll risk explicitly. Date-tagged aliases (`python-slim-trixie:3.13-2026-11-03`) remain a future story — deferred until a consumer explicitly asks for them.

## Beaconry integration (reverse dependency)

Forge is designed to be scanned by [Beaconry](https://github.com/bb-claw/beaconry). When Beaconry's scout reports a finding against a Forge image, the finding should link to Forge's published scan attestation so the operator can see exactly which package version was present at scan time and whether a patched build has since been released. This drives one API constraint: the scan attestation must be fetchable by digest alone, without authentication, from GHCR's public pull endpoint.
