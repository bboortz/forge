# Forge

Minimal, continuously patched container base images — rebuilt daily, scanned on every build, attestations published alongside every digest.

Forge solves a specific problem: upstream base images (Google distroless, Docker Hub official) patch on *their* schedule, not yours. A CVE lands in Debian `sid`, gets backported to `trixie` in two weeks, and reaches your distroless image two weeks after that. Forge short-circuits this by building its own runtime layers daily from the freshest available packages — including pulling fixes from `sid` before they're backported — and publishing the grype scan result with every push.

---

## How it works

Every image is a two-stage build:

```
Stage 1 — builder     python:3.13-slim-trixie (full apt, curl, pip)
                       ↓ apt-get upgrade + pinned sid packages where needed
                       ↓ install application dependencies

Stage 2 — runtime     FROM scratch
                       COPY only what Python needs to run:
                         interpreter, stdlib, libc, libssl, libm, ld-linux
                         + statically linked binaries (no .so dependencies)
```

The runtime stage has no shell, no package manager, no dpkg database. `docker exec` drops you into nothing. grype finds no OS-level CVEs because there is no OS package metadata to scan — only the Python packages you installed, via PyPI.

A GitHub Actions workflow rebuilds every image daily at 03:00 UTC with `--pull`. When a patched library lands in Debian, it reaches a Forge image within 24 hours without any manual intervention.

---

## Images

| Image | Shape | Size | Rebuilt | Attested |
|---|---|---|---|---|
| `ghcr.io/bboortz/python:3.13-slim-trixie`    | `python:3.13-slim-trixie` + `apt upgrade`                                     | ~121 MB | Daily 03:00 UTC | ✓ |
| `ghcr.io/bboortz/python:3.13-scratch-trixie` | Two-stage, `FROM scratch` runtime (interpreter + stdlib + libs + CA bundle + pip) | ~45 MB  | Daily 03:00 UTC | ✓ |

Every published digest ships with:
- A syft CycloneDX SBOM attached as a cosign attestation (predicate type `cyclonedx`)
- A grype JSON scan result attached as a cosign attestation (predicate type `vuln`)
- A keyless cosign signature over the digest (GHA OIDC via Sigstore Fulcio + Rekor transparency log)

The scratch variant has **no shell**, **no apt**, **no dpkg database** — `grype` against the base layer reports zero Debian-source matches, so every CVE a consumer sees is a PyPI dep they installed themselves. The slim variant keeps shell + apt for builder stages and interactive debugging.

Roadmap: selective `sid` pin against a current CVE (FG-004), `nginx:stable`, `postgres:18`. See [`docs/plan/IDEAS.md`](docs/plan/IDEAS.md).

---

## Quick start

### Slim variant — when you need pip + apt + shell

```dockerfile
FROM ghcr.io/bboortz/python:3.13-slim-trixie
COPY app.py /app/app.py
CMD ["python3", "/app/app.py"]
```

### Scratch variant — minimal attack surface, pip still works for wheels

```dockerfile
FROM ghcr.io/bboortz/python:3.13-scratch-trixie
# pip install works at runtime for wheel-only packages:
#   docker run --rm <image> pip install --target /opt/pkgs requests
COPY app.py /app/app.py
CMD ["python3", "/app/app.py"]
```

Daily rebuilds move the tag's digest, so pin by digest (`@sha256:...`) in production if you need reproducibility. The attached SBOM + scan + signature are preserved across rebuilds — they describe the new digest.

### Verify any image before pulling

```bash
cosign verify \
  --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/bboortz/python:3.13-scratch-trixie   # or :3.13-slim-trixie
```

> Requires `cosign` **v2.x**. See `memory/supply-chain.md` for the cosign-version pin rationale.

---

## Why not just use Google distroless?

> For the full differentiator breakdown with measurable claims and trade-offs, see [`docs/differentiators.md`](docs/differentiators.md).

Google distroless is excellent. Forge builds on the same idea with two differences:

**Patch speed.** Google distroless rebuilds every ~2 days and depends on Debian backporting fixes from `sid` to `trixie`. When a fix lands in `sid` and has not yet been backported, distroless remains vulnerable. Forge pulls directly from `sid` for the affected package while staying on `trixie` for everything else. The fix in `sid` becomes available in a Forge image within 24 hours of the Debian package upload.

**Proof.** Every Forge image ships with a timestamped grype scan result signed alongside the digest. You don't have to trust the claim — you can reproduce the scan against the published digest and verify the signature independently.

---

## Why not Chainguard?

[Chainguard](https://chainguard.dev) is the right choice if you want Wolfi-based images (musl libc, apk packages). Forge targets workloads that need Debian/glibc compatibility — existing shared library assumptions, `.deb` packaging workflows, or regulated environments that require a Debian CVE tracking baseline (BSI, Common Criteria).

---

## Self-hosting

The full build pipeline is open source. To run your own Forge registry:

```bash
git clone https://github.com/bboortz/forge
cd forge
cp .env.example .env          # set GHCR_TOKEN, COSIGN_KEY
make build                    # build all images locally
make scan                     # run grype, output attestations
make push                     # push to your registry
```

The GitHub Actions workflow at `.github/workflows/build.yml` runs the same `make build && make scan && make push` sequence on a daily cron. Self-hosting requires a registry (GHCR, ECR, or any OCI-compliant registry) and a cosign key pair.

---

## Beaconry integration

Forge images are designed to work with [Beaconry](https://github.com/bb-claw/beaconry), a fleet-wide CVE scanner for container hosts. When a Beaconry scout reports a finding against a Forge image, the finding links directly to the image's published scan attestation — showing exactly which package version was present at scan time and whether a patched build has since been released.

---

## Roadmap

- [ ] `nginx:stable` variant (Debian-based, FROM scratch runtime)
- [ ] `postgres:18` variant
- [ ] Automatic PR raised against dependent repos when a patched image is published
- [ ] EU-hosted registry mirror (Frankfurt) for data-sovereignty requirements
- [ ] BSI-aligned compliance report export (PDF) for audit use

---

## License

Apache 2.0. Build pipeline, Dockerfiles, and scan tooling are all open source. Use them, fork them, run your own.
