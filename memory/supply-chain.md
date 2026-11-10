*Scan, SBOM, sign, verify — the four acts every Forge image must perform before it's considered published.*

**⚠️ Cosign pin — review due 2027-05-17.** Both CI (`build.yml`) and local (`make sign-local` / `make verify`) are pinned to cosign **v2.6.5** (bumped from v2.4.3 by FG-041 to patch [GHSA-fx35-mq7g-6g98](https://github.com/sigstore/cosign/security/advisories/GHSA-fx35-mq7g-6g98), a HIGH verification-bypass CVE fixed in v2.6.5). v2.x is actively dual-maintained alongside v3.x — pinning to v2.x latest keeps us in-security with no consumer-side CLI change needed. v3 migration deferred to this review cycle: no concrete trigger (no consumer ask, no v3-only feature we need). v3.1.x reads both v2 and v3 signature formats, so any consumer CLI ≥ v2.4 can verify. Re-evaluate on review date OR immediately if: Sigstore announces v2 EOL, a consumer explicitly asks for v3-format sigs, or a HIGH/CRITICAL CVE lands on the pinned v2.x with fix v3-only. FG-041's acceptance test fails CI 7 days before the review date to prevent silent drift (see CAP `ci.cosign-pin-drift-gate`).

## Flow

```
build  →  grype scan  →  syft SBOM  →  cosign sign  →  push  →  cosign verify (gate)
```

Every digest the registry serves has:
- A grype scan result attached via `cosign attest --predicate scan.json --type vuln`
- A syft SBOM attached via `cosign attest --predicate sbom.json --type cyclonedx`
- A signature over the digest via `cosign sign` (keyless, OIDC)

## grype scan step

```bash
grype <image>:<tag> -o json --fail-on high > scan.json
```

- `--fail-on high` **does not** gate publish-time scans — nightly builds publish even when scans find issues, because the whole point is to surface what's there. The scan result goes into the attestation; the operator decides.
- `--fail-on high` **does** gate PR builds — a PR that introduces a new HIGH or CRITICAL vs. the previous digest fails the merge check. Baseline: scan of the current `:latest` from GHCR, pulled fresh in CI.
- grype DB is cached in `~/.cache/grype` on the runner. We let grype auto-update per run.

## Go stdlib CVE triage (Debian-packaged Go binaries)

Every compiled Go binary embeds the stdlib it was built against, so grype's Go cataloger reports `stdlib go1.24.x` for Debian-packaged exporters (`prometheus-ipmi-exporter`, `prometheus-alertmanager`, `prometheus`, `prometheus-node-exporter`) even though the scratch image carries no Go toolchain. These findings CANNOT be fixed by us — we don't rebuild the binaries; Debian does. The fix lands when Debian bumps their Go toolchain and rebuilds the exporter packages; our daily `--pull` picks it up automatically.

Before adding a waiver for a Go CVE, **check the GOOS scope** at `https://vuln.go.dev/ID/<GO-id>.json` — look at `.affected[].ecosystem_specific.imports[].goos`:

- Present and includes `"windows"` only (e.g. **GO-2026-6604** affecting `os.Root.Mkdir` Windows junctions) → **FALSE POSITIVE** on our linux/amd64 images. Waive via `PROMISES.yaml`'s `absence.os-cves.waivers` with reason citing the official `goos` declaration.
- Absent or includes linux (e.g. **GO-2026-4337** TLS session resumption, **GO-2026-6612** HTTP/2 flow control) → **REAL** vulnerability if the code path is reachable. Don't waive; accept in `scan-baseline.json` with an issue tracking the Debian-Go-toolchain bump.

**Waiver template** (shape validated by `scripts/verify-contracts.py`):

```yaml
- id: absence.os-cves
  ...
  waivers:
    - cve: GO-YYYY-NNNN
      reason: "Windows-only Go stdlib CVE (per official Go advisory DB: goos=[windows]; affected symbols live under internal/syscall/windows). Image is linux/amd64 only."
      until: "YYYY-MM-DD"  # 6-12 months out
```

For `-slim` variants that use `scan.nonzero-accepted` instead of `absence.os-cves` (e.g. cadvisor-slim-trixie, ipmi-exporter-slim-trixie), these CVEs flow through `scan-baseline.json` and don't need explicit waiver entries.

**Forge's own scan-regression gate currently uses a dpkg-only SBOM** (see `syft dir:/ --override-default-catalogers dpkg-db-cataloger`) so Go stdlib CVEs are invisible to it. External scanners like Beaconry use the full image scan and will flag them. The waiver mechanism serves two purposes: (1) explicit documentation for operator/auditor inspection; (2) future-proofing if we ever extend forge's SBOM to include Go modules.

## syft SBOM step

```bash
syft <image>:<tag> -o cyclonedx-json > sbom.json
```

Output format is CycloneDX JSON (not SPDX, not syft-native). Rationale: CycloneDX is the format Beaconry's hub expects on ingest, and matches most downstream tooling.

## cosign — keyless signing via GHA OIDC

Inside `.github/workflows/build.yml` (daily cron and merge-to-main publish):

```yaml
permissions:
  id-token: write     # OIDC token for keyless signing
  packages: write     # push to GHCR
  contents: read

- uses: sigstore/cosign-installer@v3
- run: |
    cosign sign --yes ${{ env.IMAGE_DIGEST }}
    cosign attest --yes --predicate scan.json --type vuln ${{ env.IMAGE_DIGEST }}
    cosign attest --yes --predicate sbom.json --type cyclonedx ${{ env.IMAGE_DIGEST }}
```

`IMAGE_DIGEST` must be the content-addressable digest (`ghcr.io/.../image@sha256:...`), not the tag. Signing a tag is unsafe — the tag can be moved after signing.

## Downstream verify (the public contract)

```bash
cosign verify \
  --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/bboortz/<image>:<tag>
```

Two levers that break this if you touch them:
- **Workflow file path**: the `--certificate-identity` is tied to the exact workflow file. Moving `build.yml` elsewhere breaks every consumer's verify command.
- **Repository name / owner**: changes the identity URL. Treat `bboortz/forge` as a stable public identifier.

If either must change, run a migration period where the old identity is also valid (sign with both, document both) for at least 90 days.

## Local developer flow

`make verify` runs cosign-verify against the just-signed local digest, using the keyless identity derived from the workflow. For out-of-CI testing (no OIDC token), the Makefile has a `make sign-local` target that uses a local cosign key pair under `.cosign/` (gitignored). Local-signed digests are never pushed to `ghcr.io/bboortz/` — only to a local registry.

## Why keyless (not stored keys)

Keyless signing (OIDC → short-lived certificate from Fulcio → signature stored in Rekor) means:
- No long-lived private key sitting in GHA secrets to leak
- Transparency log entry via Rekor is a built-in audit trail
- Verifier identity is bound to the workflow path, not to key custody

Trade-off: offline verification is harder (needs Rekor connectivity by default — can be relaxed with `--insecure-ignore-tlog`, but that defeats the point). Operators who require fully air-gapped verify can fall back to the stored-key path; we do not promise that flow in V1.

## Non-goals (V1)

- SLSA Level 3+ provenance beyond what cosign-attest ships by default. We attach vuln and SBOM predicates; we do not currently publish a separate SLSA provenance predicate. On the roadmap if a user asks.
- In-toto layouts, reproducible builds, source-code attestation. Daily rebuild + public workflow is our transparency story.
