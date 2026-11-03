# Forge — product differentiators

The four things that make Forge different, in priority order. Each has a claim you can measure, a comparison baseline, and the trade-off that comes with it.

---

## 1. Patch speed — sid pinning + daily rebuild

**Claim.** When a CVE fix lands in Debian `sid`, a Forge image carries that fix within 24 hours — even if Debian hasn't backported it to `trixie` yet.

**How we prove it.** For every active sid pin under `images/<name>/sid-pins/`, the pin file names the CVE it addresses and the date it was added. The `make verify-sid-pins` gate makes those fields required. Point at the file to show what we're pinning and why.

**Baseline we beat.**
- Google distroless: ~2-day rebuild cadence, waits for `trixie` backport before the fix propagates. If a CVE is in `sid` but not yet in `trixie`, distroless remains vulnerable.
- Vanilla `python:3.13-slim-trixie`: rebuilt when Docker Hub decides to, with no sid-pinning option.

**What it costs us.** Pins decay silently if nobody removes them. A pin that references a CVE older than 60 days triggers a review signal; the pin either comes out (backport landed) or gets refreshed (newer sid version supersedes it).

---

## 2. Verifiable supply chain — scan + SBOM + signature per digest

**Claim.** Every published digest ships with three attestations: a grype CVE scan, a syft CycloneDX SBOM, and a cosign signature. You don't have to trust the vendor — you can reproduce the scan and verify the signature from any workstation with cosign installed.

**How we prove it.**

```bash
cosign verify \
  --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/bboortz/python3.13:latest
```

The identity string is bound to the exact workflow file. Any digest that doesn't verify against that identity didn't come from Forge's pipeline.

**Baseline we beat.**
- Most Docker Hub official images: no attestations attached by default — trust the maintainer, or re-scan yourself.
- Google distroless: signed, but the attestation surface is less uniform across image types; grype scan is not attached as a predicate alongside the signature.

**What it costs consumers.** Verifying requires `cosign` installed and (by default) network access to Rekor's transparency log. Fully air-gapped verification needs a stored-key fallback that we do not promise in V1.

---

## 3. Minimal attack surface — `FROM scratch` runtime

**Claim.** The runtime stage has no shell, no package manager, no dpkg database. grype running against the runtime image finds **zero OS-level CVE candidates** because there is no OS package metadata to scan. Every finding is a PyPI dependency the consumer installed — actionable, not noise.

**How we prove it.** Run `grype ghcr.io/bboortz/python3.13:latest -o json` on a freshly built image before any application layer is applied. The `matches[]` array against the base image is empty.

**Baseline we beat.**
- `python:3.13-slim-trixie`: ships `apt`, `dpkg`, shell, package database. grype enumerates every Debian package even on a fresh image.
- Google distroless: similarly minimal, so this is parity rather than a win — the differentiator stacks when combined with (1).

**What it costs consumers.** No `docker exec` for debugging. The `-slim` variant trades this away and keeps a shell, with the same scan+sign treatment, for operators who need one.

---

## 4. Debian/glibc baseline — regulated-environment target

**Claim.** Forge targets workloads that need glibc compatibility and a Debian CVE tracking baseline (BSI, Common Criteria): existing `.so` assumptions, `.deb` packaging workflows, Debian Security Tracker as the authoritative advisory feed.

**How we prove it.** Base is `python:3.13-slim-trixie`; the sid-pin channel is Debian unstable; the CVE tracker is Debian Security Tracker + NVD. No Wolfi, no Alpine, no musl.

**Baseline we're different from.**
- Chainguard: Wolfi, musl libc, apk packages. The right choice for a different niche — not for glibc-dependent workloads or Debian-aligned compliance.
- Alpine-based images in general: musl breaks a lot of common Python wheels (manylinux assumes glibc), CGO assumptions, Node native modules.

**What it costs us.** We can't claim "smallest possible" image size — musl + apk beats glibc + apt on raw bytes. Our pitch is "small enough + Debian-native," not "smallest."

---

## What we are explicitly not

- A general-purpose minimal distro — that's Chainguard / Wolfi
- A SLSA L3+ provenance platform — keyless cosign + Rekor is our transparency story; no separate in-toto layout in V1
- A rolling-release experiment — we pin `trixie` and sid-pin surgically; we don't rebase on `sid`
- An air-gapped-first signing scheme — keyless OIDC is primary; a stored-key fallback is a request-driven V2
