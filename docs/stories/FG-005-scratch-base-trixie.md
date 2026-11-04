---
id: FG-005
slug: scratch-base-trixie
status: shipped
owner: bboortz
created: 2026-11-04
---

# FG-005 — scratch-base-trixie: shared signed foundation for every Forge scratch image

Introduces `ghcr.io/bboortz/scratch-base-trixie:0.1` (+ `:latest` + arch variants). The strict intersection of the three existing scratch closures (python-scratch-trixie, nginx-scratch-trixie, postgres-scratch-trixie): dynamic linker, core glibc (sans libutil — not needed by nginx), TLS trust, common compression (libz + libzstd), DNS resolution, zoneinfo, minimal `/etc/passwd`+`/etc/group` (root + nobody). Every Forge scratch derivative preserves its literal `FROM scratch` runtime line and composes via `COPY --from=scratch_base / /` + an image-specific overlay.

Deliberately lands AFTER FG-006 (nginx) and FG-007 (postgres) rather than before, so the baseline is the strict intersection of three real closures rather than a speculative first pass. All three derivative smoke suites still pass unchanged on top of the baseline.

## 9 canonical answers

1. **Who** — Forge maintainer adding future scratch variants (redis, go, caddy, …) who gets a signed, tested foundation to start from; security engineer auditing the shared guarantee of every Forge scratch image against a single digest.
2. **When** — on every PR / pre-push / daily cron; the derivative images build their baseline first via `scripts/build-image.sh`'s `depends_on` resolution.
3. **What success looks like** —
   - `ghcr.io/bboortz/scratch-base-trixie:0.1` (+ `:latest`, `-amd64`, `:latest-amd64`) publishes; ≤ 25 MB
   - 4 smoke tests pass against the baseline (contents_required_files, contents_no_shell, contents_zero_os_cves, size)
   - python-scratch-trixie's Dockerfile begins `FROM scratch + COPY --from=scratch_base`; all 8 FG-003 smoke tests pass
   - nginx-scratch-trixie: same pattern; all 6 FG-006 smokes green
   - postgres-scratch-trixie: same pattern; all 5 FG-007 smokes green
   - `docs/differentiators.md` documents the baseline layer so the "FROM scratch" differentiator stays honest
4. **Urgency** — foundation tier; enables future scratch variants (redis, go, caddy, every forthcoming server image) to inherit the shared guarantee instead of rebuilding closure work.
5. **Happy path** —
   1. Build `images/scratch-base-trixie/` standalone; 4 file-contents smokes pass; size ~13 MB.
   2. Teach `scripts/build-image.sh` to resolve `depends_on:` in image.yaml — builds dependencies first.
   3. Teach `scripts/_image_yaml.sh` with an `image_yaml_depends()` helper.
   4. Add `SCRATCH_BASE_REF` build-arg to python/nginx/postgres Dockerfiles; add `FROM ${SCRATCH_BASE_REF} AS scratch_base`; `COPY --from=scratch_base / /` BEFORE the image-specific `COPY --from=builder /out /`. Overwrite `/etc/passwd`+`/etc/group` from the builder COPY when the image needs its own service user.
   5. Add `depends_on: [scratch-base-trixie]` to each derivative's image.yaml.
   6. `scripts/build-image.sh` conditionally drops `--pull` when the SCRATCH_BASE_REF resolves to a `forge-local/*` image (the legacy docker builder tries to pull even locally-present images; doesn't exist on the "forge-local" registry; fails).
   7. GHA `.github/workflows/build.yml` splits into two stages: `publish-base` (just scratch-base-trixie), `publish-derivatives` (matrix over the rest, `needs: publish-base`). Ensures baseline is on GHCR before derivatives try to `FROM` it on a cold runner.
   8. `docs/differentiators.md` gets a paragraph explaining the baseline layer so consumers understand that `FROM scratch` in each derivative is literal, but compositionally rests on a shared signed artifact.
6. **Edge cases / failure modes** —
   - Legacy docker builder aborts on `FROM forge-local/scratch-base-trixie:0.1` with "pull access denied" when `--pull` is passed and the ref isn't in a real registry. Resolved by `scripts/build-image.sh` dropping `--pull` if the ref resolves locally.
   - Stale `libutil.so.1` in baseline: first draft included it, but nginx ldd closure doesn't. Tightened: libutil moved into python + postgres overlays. Strict intersection rule honored.
   - `/etc/passwd` overwrite collisions: baseline has only root+nobody; derivatives OVERWRITE with their service-user augmented version (last COPY wins in docker). Preserves correct final /etc identity per image.
   - Daily cron ordering on GHA: baseline must publish before derivatives attempt `FROM ghcr.io/bboortz/scratch-base-trixie:latest`. Enforced via matrix split + `needs:` in build.yml.
7. **Out of scope** — multi-arch (arm64, FG-008); sid pins; a `scratch-base-bookworm` variant (future); nginx/postgres builder-variant images; smoke tests that run inside the baseline (no exec, no feasible interactive test).
8. **How we know it's done** — see Gherkin + the FG-005 acceptance test.
9. **Capabilities** —
   - NEW `build.scratch-baseline` — shared signed baseline for every Forge scratch image, strict intersection of derivative closures
   - NEW `test.scratch-contents` — file-contents smoke style for images with no exec (`docker save | tar tf`)
   - EXT `image.zero-os-cves` — now holds on baseline AND every derivative built on it
   - EXT `test.image-smoke-suite` — baseline uses the contents-style smoke; derivatives keep runtime-style
   - EXT `test.size-budget` — baseline adds a tight 25 MB absolute ceiling

## Gherkin acceptance

```
Scenario: baseline image dir exists
  Given the repo at HEAD
  Then images/scratch-base-trixie/ exists with Dockerfile + image.yaml + tests/

Scenario: baseline builds and passes contents smokes
  Given scripts/build-image.sh scratch-base-trixie runs
  Then forge-local/scratch-base-trixie:0.1 exists
   And its 4 smoke scripts (contents_required_files, contents_no_shell,
       contents_zero_os_cves, size) all pass

Scenario: each scratch derivative composes on the baseline
  Given images/{python,nginx,postgres}-scratch-trixie/Dockerfile
  Then each contains ARG SCRATCH_BASE_REF + FROM ${SCRATCH_BASE_REF}
   And each has a COPY --from=scratch_base line
   And each image.yaml declares depends_on: scratch-base-trixie

Scenario: every derivative's smoke suite still passes on the refactored base
  Given each derivative rebuilt against forge-local/scratch-base-trixie:0.1
  Then python-scratch-trixie's 8 smokes pass
   And nginx-scratch-trixie's 6 smokes pass
   And postgres-scratch-trixie's 5 smokes pass

Scenario: baseline image size ≤ 25 MB
  Given the baseline built
  Then docker image inspect size ≤ 25_000_000 bytes

Scenario: differentiators doc documents the baseline layer
  Given docs/differentiators.md
  Then it references scratch-base-trixie and explains the composition
```

## References

- Plan: [`docs/plan/FG-005-scratch-base-trixie-plan.md`](../plan/FG-005-scratch-base-trixie-plan.md)
- Red test: [`tests/acceptance/test_FG_005_scratch-base-trixie.sh`](../../tests/acceptance/test_FG_005_scratch-base-trixie.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
