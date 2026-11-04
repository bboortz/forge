# FG-011 — Plan: librt.so.1 ABI stub for manylinux compat

**Story**: [`docs/stories/FG-011-librt-manylinux-compat.md`](../stories/FG-011-librt-manylinux-compat.md)
**Status**: in-progress
**Branch**: `feat/FG-011-librt-manylinux-compat`

## Design delta

One lib added to python-scratch-trixie's COPY loop, one smoke, one promise, one CAP.

```
images/python-scratch-trixie/Dockerfile
  + librt.so.1 in the python-specific lib COPY loop
  + comment explaining why (glibc 2.34 merge, manylinux2014 pins to 2.17)

images/python-scratch-trixie/tests/smoke_librt_manylinux.sh
  + verifies file in layers (docker save + tar tf)
  + verifies ctypes.CDLL('librt.so.1') succeeds at runtime

images/python-scratch-trixie/PROMISES.yaml
  + promise runtime.librt-abi-stub → smoke_librt_manylinux.sh
  + version bumped 0.1 → 0.2 (semver-gated minor — added a promise)

docs/CAPABILITIES.md
  + CAP image.manylinux-wheel-compat

tests/acceptance/test_FG_011_librt-manylinux-compat.sh
  + Gherkin scenarios as shell assertions
```

Image size delta: **+14.5 KB** (empty-stub librt.so.1). Below measurement noise in `smoke_size.sh` (60 MB ceiling).

## Alternatives rejected

- **Install from pip at wheel-install time** (lazy): consumers would hit a broken image on first manylinux2014 install; the point is shipping it.
- **Add librt to the baseline**: not every scratch derivative carries Python-ecosystem concerns (nginx, postgres don't). Keeping it image-specific is the FG-005 principle.
- **Build librt from source ourselves**: the Debian stub IS the ABI stub we want; no source build needed. Same provenance as every other lib we COPY.
- **Replace the stub with the libc symbols statically**: can't — the loader resolves `NEEDED librt.so.1` by filename, not by symbol. The file must exist.
- **Run a real `pip install numpy` as the preflight**: 20 MB network fetch per CI tick, slow, and we don't own numpy. `ctypes.CDLL` is the layer that actually fails — that's what we assert.

## Breaking changes

None. Size budget unchanged; tag unchanged; entrypoint unchanged.

## Merge plan

Single PR, single commit. Tests pass locally before push. Pre-push runs `make check-strict` (clean cache rebuild + all smokes incl. new preflight).

## Rollout

Standard: PR to dev → auto-merge on green → operator triggers `release.yml` + `build.yml` → `ghcr.io/bboortz/python-scratch-trixie:3.13` gets the stub on next publish.

Post-publish check (included in acceptance test with `PUBLISHED=1`):
```
docker run --rm --entrypoint=python3 ghcr.io/bboortz/python-scratch-trixie:3.13 \
  -c "import ctypes; ctypes.CDLL('librt.so.1'); print('ok')"
```

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: librt stub present in image | `images/python-scratch-trixie/tests/smoke_librt_manylinux.sh` | ✅ |
| Scenario: dlopen succeeds at runtime | smoke (same file) | ✅ |
| Scenario: PROMISES.yaml reflects guarantee + bump | acceptance test grep + verify-contracts | ✅ |
| Scenario: verify-contracts stays green | FG-011 acceptance | ✅ |
| Scenario: semver gate accepts 0.1 → 0.2 bump | FG-011 acceptance + `--compare` mode | ✅ |
| NEW CAP `image.manylinux-wheel-compat` | docs/CAPABILITIES.md + PROMISES.yaml caps entry | ✅ |
| `make check-strict` green on cold cache | local | ✅ |
| Post-publish ctypes.CDLL check against ghcr.io digest | post-publish, opt-in `PUBLISHED=1` | ⚠️ post-publish |
