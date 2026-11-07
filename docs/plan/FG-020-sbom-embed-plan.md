# FG-020 — Plan: embed syft SBOM in runtime

**Story**: [`docs/stories/FG-020-sbom-embed.md`](../stories/FG-020-sbom-embed.md)
**Status**: in-progress
**Branch**: `feat/FG-020-sbom-embed`

## Design delta

### Dockerfile pattern (applied to 4 Forge-native images)

Add in the builder stage:

```dockerfile
# FG-020: syft generates an SBOM of the full builder filesystem (dpkg-tracked
# packages with their actual Debian versions, including backports like
# -deb13u10). The SBOM is COPY'd into the scratch runtime so grype's Debian
# matcher can honor backports — otherwise it falls back to NVD-CPE which
# doesn't know about Debian's version suffixes.
ARG SYFT_VERSION=v1.57.0
RUN curl -sSfL "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
      | sh -s -- -b /usr/local/bin "${SYFT_VERSION}" \
    && syft dir:/ -o cyclonedx-json > /sbom.json
```

Add in the runtime stage:

```dockerfile
COPY --from=builder /sbom.json /sbom.json
```

Scope: `python-scratch-trixie`, `nginx-scratch-trixie`, `postgres-scratch-trixie`, `scratch-base-trixie`. The python-slim-trixie is a one-stage image and doesn't need the dance — it already has dpkg for grype to read directly.

### `scripts/scan-regression.py` changes

```python
def resolve_grype_source(image_ref, image_dir):
    """Return a grype --source argument. If /sbom.json ships in the image,
    extract it to tmp and return sbom:<path>. Else return image_ref."""
    tmp = Path(tempfile.mkdtemp())
    cid = subprocess.run(
        ["docker", "create", image_ref], capture_output=True, text=True, check=True
    ).stdout.strip()
    try:
        cp = subprocess.run(
            ["docker", "cp", f"{cid}:/sbom.json", str(tmp / "sbom.json")],
            capture_output=True, text=True,
        )
        if cp.returncode == 0:
            return f"sbom:{tmp / 'sbom.json'}"
        return image_ref  # fallback
    finally:
        subprocess.run(["docker", "rm", cid], capture_output=True)
```

Then `run_grype()` takes the resolved source: `grype <resolved-source> -o json`.

### Baseline regeneration

After the Dockerfile + script changes land:

```
for img in python-scratch-trixie nginx-scratch-trixie postgres-scratch-trixie \
           scratch-base-trixie beaconry-scout beaconry-hub \
           beaconry-telegram-mock python-slim-trixie; do
    bash scripts/build-image.sh "${img}"
    python3 scripts/scan-baseline-update.py "${img}"
done
```

Expected changes:
- `nginx-scratch-trixie`: 2 CRIT → 0 (nginx CVE-{15176,42533} resolved via Debian matcher)
- `beaconry-scout`, `beaconry-hub`: 1 CRIT → 1 (GO-2026-6888 remains; Go matcher wasn't the issue)
- `python-scratch-trixie`, `python-slim-trixie`, `postgres-scratch-trixie`, `scratch-base-trixie`, `beaconry-telegram-mock`: 0 → 0 (no change)

### Docs

- `memory/supply-chain.md`: new section "SBOM source of truth = builder stage" with the Chainguard-like rationale.
- `docs/baseline-contract.md`: scratch-base-trixie's contract gains `/sbom.json` as a promised file (new entry in PROMISES.yaml too).

## Alternatives rejected

- **Scan the builder stage directly instead of embedding** — would require building the `--target=builder` for every scan-regression run, doubling build time. Embedded SBOM is a one-time build cost, consumed indefinitely.
- **Post-process grype with Debian-tracker API lookups** — needs network at scan time, chattier, and still less complete than SBOM-level matching.
- **Filter nvd:cpe entirely** (Option A, previously rejected) — loses legitimate upstream-matched findings on raw binaries.
- **Modify beaconry Dockerfiles to embed SBOM too** — upstream change; out of scope. Beaconry images keep current behavior (fallback).

## Breaking changes

- Published image size +~200 KB per Forge-native scratch image. Within existing ceilings (nginx-scratch-trixie budget is 25 MB; currently 15.6 MB).
- Published SBOM attestation shape changes: moves from "thin runtime scan" to "rich builder scan". Beaconry's scout may need to adapt if it specifically relied on the thin shape — unlikely, and addressable with a one-line read-strategy change on their side.

## Rollout

- Merge to dev → smart-check-strict (or CI full) rebuilds affected images + regenerates baselines.
- Release to main → build.yml cron publishes new images with embedded SBOMs.
- Downstream Beaconry attests via its own scout; nothing breaks there.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| /sbom.json ships in 4 Forge-native scratch images | FG-020 acceptance § section 1 | ⏳ |
| scan-regression uses SBOM when present | § 2 | ⏳ |
| nginx false positives resolved | § 3 | ⏳ |
| externally-sourced fallback works | § 4 | ⏳ |
| 8 baselines regenerated with the SBOM path | commit | ⏳ |
| memory/supply-chain.md documents the policy | commit | ⏳ |
| `make check-strict` green | local | ⏳ |
