*Scan, SBOM, sign, verify — the four acts every Forge image must perform before it's considered published.*

**⚠️ Cosign pin — review due 2026-11-17.** Both CI (`build.yml`) and local (`make sign-local` / `make verify`) are pinned to cosign **v2.4.3**. v3.x stores signatures as OCI 1.1 referrers (no `.sig` tag) and dropped `--tlog-upload=false`, which would break both consumer-side verify with v2 clients and the local sign-local round-trip. Review path: upgrade everything to v3 + rewrite sign-local around a tlog-less signing-config, or renew the v2 pin.

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
