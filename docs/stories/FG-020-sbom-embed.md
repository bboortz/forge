---
id: FG-020
slug: sbom-embed
status: shipped
owner: bboortz
created: 2026-11-07
---

# FG-020 — Embed syft SBOM in runtime; scan-regression honors Debian backports

Closes the FG-019 false-positive on Debian-backported packages. Grype's NVD-CPE matcher doesn't know about Debian's package-version suffixes (`-deb13u10`), so for scratch runtime images (which deliberately strip dpkg), it reports nginx 1.26.3 as vulnerable to CVE-2026-{15176,42533} even though trixie-security carries the backport fix.

**Fix (Option B — embedded SBOM + grype):** builder stage runs syft at build time (where dpkg is present), writes `/sbom.json`; runtime stage `COPY --from=builder /sbom.json /sbom.json`. The SBOM carries full dpkg metadata — package name, full Debian version (`1.26.3-3+deb13u10`), origin. `scan-regression.py` detects the file in the image, extracts it, invokes `grype sbom:<path>` instead of `grype <image>`. Grype's Debian matcher activates against the SBOM's `deb`-type packages and correctly resolves Debian-backport status.

Bonus: our cosign SBOM attestation (syft output) was previously thin because syft ran against the dpkg-less scratch runtime. With FG-020, the attachable SBOM is the rich one from the builder — downstream consumers (Beaconry's scout, operators auditing) get real package detail.

## 9 canonical answers (compressed)

1. **Who** — anyone running scan-regression (PR CI, pre-push, nightly, local triage); downstream consumers of our SBOM attestations.
2. **When** — every PR / pre-push / nightly / daily cron publish.
3. **Success looks like** —
   - All 4 Forge-native scratch images ship `/sbom.json` in the runtime (python-scratch, nginx-scratch, postgres-scratch, scratch-base).
   - `scan-regression.py` detects `/sbom.json` and uses it for grype; falls back to image scan when absent (externally-sourced images without the embed).
   - After regenerating baselines: nginx-scratch-trixie goes from **2 CRITICAL → 0** (CVE-2026-15176 + CVE-2026-42533 disappear because the Debian matcher sees `1.26.3-3+deb13u10` as fixed).
   - Image size impact: +~200 KB SBOM per image. Within existing ceilings.
   - FG-019's GO-2026-6888 on beaconry images stays reported (it comes via grype's Go matcher, not NVD-CPE — out of scope for this FG).
4. **Urgency** — high; FG-019's operational value depends on this landing.
5. **Happy path** —
   1. Each Forge-native Dockerfile's builder stage installs pinned syft (via curl) + runs `syft dir:/ -o cyclonedx-json > /sbom.json`.
   2. Runtime stage: `COPY --from=builder /sbom.json /sbom.json`.
   3. `scripts/scan-regression.py`: new helper `extract_sbom(image_ref)` uses `docker create + docker cp + docker rm`; if file present → `grype sbom:<path>`; else → `grype <image>` (fallback).
   4. `scripts/scan-baseline-update.py` reuses the same loader.
   5. Regenerate 8 baselines.
   6. Docs: `memory/supply-chain.md` + `docs/baseline-contract.md` gain the SBOM-embed note. CAPABILITIES.md extends `scan.regression-gate`.
   7. FG-020 acceptance test.
6. **Edge cases / failure modes** —
   - Image lacks `/sbom.json` (e.g., beaconry externally-sourced) → fallback to current grype behavior; no regression in gating.
   - SBOM extraction fails (corrupt file, docker daemon weirdness) → scan-regression errors out, doesn't silently fall back.
   - Builder has extra packages the runtime doesn't (apt, build-essential, curl) → SBOM records them. This DOES slightly over-report versus "true runtime"; but this is already the state captured by cosign's SBOM attestation today, just richer. Documented as a known limitation; can filter per-image later via a /out staging-path syft scan if needed.
   - syft version churn breaks determinism → pinned syft version in Dockerfile (e.g., `v1.56.0`).
7. **Out of scope** —
   - Externally-sourced images gain `/sbom.json` embedding (would require upstream Dockerfile changes); they keep current behavior.
   - Filtering the SBOM to packages that actually land in runtime (`/out/` scope).
   - Changing the cosign attestation attachment flow (nightly build.yml) — tracked separately.
8. **Done** — FG-020 acceptance test green + `make check-strict` green + 4 regenerated baselines show 0 nginx-CVE false positives.
9. **Capabilities**:
   - NEW `scan.sbom-embed` — runtime image carries its builder-time SBOM; grype honors Debian backports
   - EXT `scan.regression-gate` — SBOM-first, image-fallback source resolution
   - EXT `sbom.cyclonedx-attest` — attested SBOM is now rich (carries dpkg metadata from builder, not sparse scratch runtime view)

## Gherkin acceptance

```
Scenario: /sbom.json ships in every Forge-native scratch image
  Given the published image
  When I inspect its filesystem
  Then /sbom.json is present
   And it's valid CycloneDX JSON
   And it lists at least one deb-type component

Scenario: scan-regression consumes SBOM when present
  Given a Forge-native scratch image with /sbom.json
  When scan-regression runs
  Then grype is invoked with sbom:<extracted-path>
   And Debian backports are honored (no NVD-CPE false positives on distro-packaged binaries)

Scenario: FG-019 false positives resolved
  Given nginx-scratch-trixie's regenerated baseline (after FG-020)
  Then CVE-2026-15176 and CVE-2026-42533 are NOT in the CRITICAL set
   And a new truly-new CRITICAL would still trigger scan-regression

Scenario: externally-sourced images fall back gracefully
  Given beaconry-scout (no /sbom.json in runtime)
  When scan-regression runs
  Then grype is invoked against the image directly (current behavior)
   And no error from missing SBOM
```

## References

- Plan: [`docs/plan/FG-020-sbom-embed-plan.md`](../plan/FG-020-sbom-embed-plan.md)
- Red test: [`tests/acceptance/test_FG_020_sbom-embed.sh`](../../tests/acceptance/test_FG_020_sbom-embed.sh)
- Depends on: FG-019 (scan-regression + baseline mechanism)
- Debian security tracker references:
  - [CVE-2026-42533](https://security-tracker.debian.org/tracker/CVE-2026-42533) — fixed in `1.26.3-3+deb13u10` via DSA-6496-1
  - [CVE-2026-15176](https://security-tracker.debian.org/tracker/CVE-2026-15176) — fixed in `1.26.3-3+deb13u10`
