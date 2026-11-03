*Locked design decisions for Forge. Source: README + initial scoping.*

## Base distribution — Debian trixie (not Wolfi, not Alpine)

Forge targets workloads that need glibc compatibility: existing `.so` assumptions, Debian packaging conventions, regulated environments requiring a Debian CVE tracking baseline (BSI, Common Criteria). Chainguard already serves the Wolfi/musl niche well — Forge does not compete there.

Consequence: our scanner coverage is NVD + Debian Security Tracker. Not Wolfi advisories, not Alpine SecDB.

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

Verification identity: `--certificate-identity https://github.com/forge-images/forge/.github/workflows/build.yml`, `--certificate-oidc-issuer https://token.actions.githubusercontent.com`. The identity string is tied to the workflow file path — if we move the workflow, we break every downstream verify. Treat the path as a stable public interface.

## Image set V1

| Image | Status | Shape |
|---|---|---|
| `python3.13` | ship | trixie builder → `FROM scratch` runtime |
| `python3.13-slim` | ship | published as-is after `apt upgrade` |
| `nginx:stable` | roadmap | Debian-based, `FROM scratch` runtime |
| `postgres:18` | roadmap | Debian-based, `FROM scratch` runtime |

Roadmap also tracks: automatic PRs against dependent repos, EU-hosted mirror (Frankfurt), BSI-aligned compliance report export.

## No `latest`-only — digests are the contract

`:latest` moves daily, so consumers who want reproducibility must pin by digest. We publish date-tagged aliases (`python3.13:2026-11-03`) alongside `:latest` so the digest is addressable by a human-readable tag. Deprecation policy for date tags: keep 90 days, then prune.

## Beaconry integration (reverse dependency)

Forge is designed to be scanned by [Beaconry](https://github.com/bb-claw/beaconry). When Beaconry's scout reports a finding against a Forge image, the finding should link to Forge's published scan attestation so the operator can see exactly which package version was present at scan time and whether a patched build has since been released. This drives one API constraint: the scan attestation must be fetchable by digest alone, without authentication, from GHCR's public pull endpoint.
