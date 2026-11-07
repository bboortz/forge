# FG-021 — Plan: docker buildx registry cache

**Story**: [`docs/stories/FG-021-ci-buildx-cache.md`](../stories/FG-021-ci-buildx-cache.md)
**Status**: in-progress
**Branch**: `feat/FG-021-ci-cache` (shared with FG-022)

## Design delta

### `scripts/build-image.sh`

```bash
# FG-021: use buildx with registry cache when BUILDX_CACHE_{FROM,TO} env is set.
# CI wires these to ghcr.io/bboortz/<image>:buildcache; local devs can opt in.
BUILDX_CACHE_FROM="${BUILDX_CACHE_FROM:-}"
BUILDX_CACHE_TO="${BUILDX_CACHE_TO:-}"

build_cmd=(docker build)
if [[ -n "${BUILDX_CACHE_FROM}${BUILDX_CACHE_TO}" ]]; then
  build_cmd=(docker buildx build --load)
  [[ -n "${BUILDX_CACHE_FROM}" ]] && build_cmd+=("--cache-from=${BUILDX_CACHE_FROM}")
  [[ -n "${BUILDX_CACHE_TO}" ]]   && build_cmd+=("--cache-to=${BUILDX_CACHE_TO}")
fi

"${build_cmd[@]}" ${PULL_FLAG} ... --tag "${IMAGE_REF}" "${BUILD_CONTEXT}"
```

### `.github/workflows/ci.yml` (full-check job)

```yaml
- uses: docker/setup-buildx-action@v3

- name: Login to GHCR for cache pull
  if: github.event.pull_request.head.repo.full_name == github.repository || github.event_name == 'push'
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
  continue-on-error: true   # fork PRs: fail quietly, cache miss acceptable

- name: Set cache env (per image; wrapped in make check-smart's affected loop)
  run: |
    # Full-check iterates images; each image's build-image.sh sees these envs
    # via per-call BUILDX_CACHE_FROM resolution.
    echo "FORGE_CACHE_FROM_PREFIX=ghcr.io/bboortz" >> $GITHUB_ENV
    if [[ "${{ github.event_name }}" == "pull_request" ]]; then
      echo "FORGE_CACHE_PUSH=0" >> $GITHUB_ENV
    else
      echo "FORGE_CACHE_PUSH=1" >> $GITHUB_ENV
    fi
```

**Where cache env resolves to per-image** — `scripts/build-image.sh` needs per-image awareness. Simplest: resolve inside the script from the image's repo name:

```bash
# After REPO/TAG resolution, before the build:
if [[ -n "${FORGE_CACHE_FROM_PREFIX:-}" ]]; then
  BUILDX_CACHE_FROM="type=registry,ref=${FORGE_CACHE_FROM_PREFIX}/${REPO}:buildcache"
  if [[ "${FORGE_CACHE_PUSH:-0}" == "1" ]]; then
    BUILDX_CACHE_TO="type=registry,ref=${FORGE_CACHE_FROM_PREFIX}/${REPO}:buildcache,mode=max"
  fi
fi
```

Script is the single integration point; CI just sets two env vars.

### `.github/workflows/build.yml` + `nightly.yml`

Both set `FORGE_CACHE_PUSH=1` (trusted events). Nightly can optionally skip cache-from if the whole point is cold-cache audit — leaving as read+write for now (nightly still catches drift via `clean-local-images`).

## Alternatives rejected

- **GHA-native `actions/cache` for docker layers** — doesn't survive across jobs properly; registry-backed cache is standard.
- **Single shared `forge-buildcache` repo on GHCR** — would mix layers across unrelated images; per-image `:buildcache` tag is cleaner.
- **`mode=min` cache** — half the storage but doesn't cache intermediate layers; defeats the point for multi-stage builds.

## Breaking changes

None. `docker build` path stays for local dev without env vars; `docker buildx build --load` is a superset.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| build-image.sh respects BUILDX_CACHE_* | FG-021 acceptance § sections 1-3 | ⏳ |
| ci.yml + build.yml + nightly.yml wire cache | FG-021 acceptance § section 4 | ⏳ |
| Fork PRs: continue-on-error for login | workflow inspection | ⏳ |
| `make check-strict` green (no cache behavior change for plain docker build path) | local | ⏳ |
| Measured post-merge CI drop | post-merge observation | ⏳ |
