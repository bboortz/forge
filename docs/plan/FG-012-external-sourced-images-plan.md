# FG-012 — Plan: externally-sourced images + beaconry-scout

**Story**: [`docs/stories/FG-012-external-sourced-images.md`](../stories/FG-012-external-sourced-images.md)
**Status**: shipped
**Branch**: `feat/FG-012-external-sourced-images`

## Design delta

### `image.yaml` grows an optional `source:` block

```yaml
# Forge-local image (current 5): unchanged
tag: "3.13"
platforms:
  - linux/amd64
depends_on:
  - scratch-base-trixie

# Externally-sourced image (new): source + depends_on; NO local Dockerfile
tag: "0.1"
platforms:
  - linux/amd64
depends_on:
  - python-scratch-trixie   # contract dep (beaconry Dockerfile FROMs it)
source:
  git: https://github.com/bboortz/beaconry
  ref: "665370e7d793968b5b8fc550fbd0582993a829fc"   # SHA (pinned)
  dockerfile: poc/scout/Dockerfile                  # path inside the clone
  context: poc/                                     # build context inside the clone
```

`ref` accepts: 40-char SHA, git tag, `latest` keyword, or any branch name. Resolved at build time to a concrete sha.

### `scripts/_image_yaml.sh` gains 4 helpers

```bash
image_yaml_source_git       <file>   # URL or empty
image_yaml_source_ref       <file>   # ref string or empty
image_yaml_source_dockerfile <file>  # defaults to "Dockerfile"
image_yaml_source_context   <file>   # defaults to "."
```

Pure awk/sed — same house style as the existing helpers. `source:` is a nested block so the parser handles indented keys.

### `scripts/build-image.sh` branches on `source:` present

Pseudocode:

```bash
if source.git set; then
  clone_dir=$(mktemp -d)
  git -C "${clone_dir}" init -q
  git -C "${clone_dir}" remote add origin "${source.git}"
  if git -C "${clone_dir}" fetch --depth=1 origin "${source.ref}"; then
    git -C "${clone_dir}" checkout -q FETCH_HEAD
  else
    # fetch-by-sha on non-tip failed → full clone fallback
    rm -rf "${clone_dir}"
    git clone --quiet "${source.git}" "${clone_dir}"
    git -C "${clone_dir}" checkout -q "${source.ref}"
  fi
  resolved_sha=$(git -C "${clone_dir}" rev-parse HEAD)
  build_context="${clone_dir}/${source.context:-.}"
  dockerfile="${clone_dir}/${source.dockerfile:-Dockerfile}"
else
  build_context="${SRC}"
  dockerfile="${SRC}/Dockerfile"
  resolved_sha="${GIT_SHA}"   # Forge's own HEAD — current behavior
fi

docker build \
  --build-arg GIT_SHA="${resolved_sha}" \
  --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
  --file "${dockerfile}" \
  --tag "${IMAGE_REF}" \
  "${build_context}"
```

The `GIT_SHA` build-arg flows into existing `LABEL org.opencontainers.image.revision="${GIT_SHA}"` lines in beaconry's Dockerfile (standard OCI convention). For externally-sourced images, the label ends up with the upstream sha — exactly what auditors need.

### `scripts/verify-image-dirs.sh` (new lint)

Rejects:
- Image dir has `source:` AND `Dockerfile` (mutually exclusive).
- Image dir has `source:` but no `ref:`.
- Image dir has `source:` with empty `git:`.
- Image dir has neither `source:` nor `Dockerfile` (dangling dir).

Wired into `make test-fast` after `verify-contracts`.

### `images/beaconry-scout/`

```
image.yaml              — source:, pinned to 665370e7..., dockerfile: poc/scout/Dockerfile, context: poc/
PROMISES.yaml           — Forge-authored audit surface
EXPECTATIONS.yaml       — depends on python-scratch-trixie@>=3.13
tests/
  smoke_readyz.sh       — `docker run -d` + wait + curl /readyz 200
  smoke_syft_bundled.sh — syft --version exits 0
  smoke_no_shell.sh     — docker save + tar inspection
  smoke_zero_os_cves.sh — grype shows zero Debian-source matches
  smoke_size.sh         — ≤ 150 MB hard ceiling
```

No local `Dockerfile`. The Dockerfile at `poc/scout/Dockerfile` in beaconry already produces exactly what we want.

## Alternatives rejected

- **Vendor a copy of beaconry's Dockerfile into Forge**: breaks the "sources stay in beaconry" constraint; duplicates maintenance; forces manual sync on every beaconry Dockerfile change.
- **Separate `source.yaml` file**: over-engineering — same image-level metadata, same parsing, same ownership. One file.
- **Require `ref` to be a sha** (reject tags/branches): too strict. Daily cron on `ref: latest` is a legitimate workflow (see memory/supply-chain.md § daily rebuild cadence) — forbidding floating refs for external images but allowing them for Forge-local ones would be inconsistent.
- **Ship beaconry-hub + beaconry-scout together**: user downscoped to scout first ("start with the simplest image"). Hub follows as FG-013.
- **Run full beaconry integration tests in Forge CI**: wrong layer. Forge validates image *shape*; beaconry's CI covers behaviour.

## Breaking changes

None. Existing 5 images are unchanged — their `image.yaml` has no `source:` and the build path stays identical.

## Merge plan

Single PR, two logical sections:
1. **Mechanism**: `_image_yaml.sh` helpers + `build-image.sh` branch + `verify-image-dirs.sh` lint + CAP registry entries + acceptance test (sections 1-3). Feature-dark without a consumer.
2. **Consumer**: `images/beaconry-scout/` dir + smokes + PROMISES/EXPECTATIONS + acceptance test sections 4-6.

Single commit is fine (both parts tested together).

## Rollout

- `images/beaconry-scout/` enters the auto-discovery matrix in `.github/workflows/build.yml` on next publish. No workflow file edit needed (per FG-003 `publish.matrix-auto-discovery`).
- First GHCR publish yields `ghcr.io/bboortz/beaconry-scout:0.1`. Cosign identity remains `.github/workflows/build.yml@refs/heads/main` — unchanged.
- Consumers verify with the standard Forge cmd:
  ```
  cosign verify \
    --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    ghcr.io/bboortz/beaconry-scout:0.1
  ```

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: source + local Dockerfile mutually exclusive | FG-012 acceptance § section 1 | ✅ |
| Scenario: source without ref rejected | FG-012 acceptance § section 2 | ✅ |
| Scenario: external build at pinned sha | FG-012 acceptance § section 3 | ✅ |
| Scenario: scout `/readyz` → 200 | `images/beaconry-scout/tests/smoke_readyz.sh` | ✅ |
| Scenario: scout ships working syft | `images/beaconry-scout/tests/smoke_syft_bundled.sh` | ✅ |
| Scenario: verify-contracts green | FG-012 acceptance | ✅ |
| NEW CAP `build.external-source` | CAPABILITIES.md + PROMISES/image.yaml usage | ✅ |
| NEW CAP `publish.external-image` | CAPABILITIES.md | ✅ |
| NEW CAP `image.beaconry-scout` + `image.beaconry-scout-bundled-syft` | CAPABILITIES.md | ✅ |
| `make check-strict` green cold cache (36 smokes including the 5 scout smokes) | local | ⏳ (verifying) |
| Post-publish: cosign verify against `ghcr.io/bboortz/beaconry-scout:0.1` | post-publish | ⚠️ |
