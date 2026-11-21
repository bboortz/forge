# FG-080 — Plan: base/scratch-alpine-3 + nginx-scratch-alpine (atomic pair)

**Story**: [`docs/stories/FG-080-nginx-scratch-alpine-and-scratch-alpine-base.md`](../stories/FG-080-nginx-scratch-alpine-and-scratch-alpine-base.md)
**Status**: ready → shipped
**Branch**: `feat/FG-080-nginx-scratch-alpine`

## Design delta

Two atomic new images. Both land in one PR because Rule 12 (post-FG-075) requires every `base/*` L3 to have ≥1 forge-internal consumer.

### `base/scratch-alpine-3` (new L3 scratch-musl overlay)

2-stage Dockerfile:
- **builder** FROMs `${BASE_ALPINE_REF}` + apk-adds `musl ca-certificates tzdata` + stages the curated closure into `/out`
- **runtime** `FROM scratch` + `COPY --from=builder /out /` + LABEL + `USER 65532`

Closure:

| Path | Source | Purpose |
|---|---|---|
| `/lib/ld-musl-x86_64.so.1` → `/lib/libc.musl-x86_64.so.1` (symlink via `cp -a`) | apk `musl` | dynamic loader |
| `/lib/libc.musl-x86_64.so.1` | apk `musl` | musl C lib |
| `/etc/ssl/certs/ca-certificates.crt` | apk `ca-certificates` | TLS trust store |
| `/etc/nsswitch.conf` + `/etc/{passwd,group,hosts,resolv.conf}` stubs | manual (minimal) | nss + name resolution |
| `/usr/share/zoneinfo/UTC` | apk `tzdata` | minimal zone |

### `nginx-scratch-alpine` (new L4 scratch runtime)

4-stage Dockerfile:
- `scratch_base_alpine` FROM `${BASE_SCRATCH_ALPINE_REF}` (overlay source)
- `builder` FROM `${BASE_ALPINE_REF}` + `apk add nginx` + ldd-closure stage + nginx conf tree staging into `/out`
- `sbom` — syft staged `/out`
- `runtime` `FROM scratch` + COPY overlay + COPY builder + /hc + USER 65532 + HEALTHCHECK + ENTRYPOINT nginx

## Alternatives rejected

- **Ship `base/scratch-alpine-3` alone, land `nginx-scratch-alpine` in a separate FG** — Rule 12 trips. Rejected.
- **nginx-scratch-alpine assembles its own musl closure inline (no overlay)** — duplicates the closure per every future scratch-musl runtime. Rejected per `memory/scratch-closures.md` baseline philosophy.
- **nginx-scratch-alpine FROMs `nginx:1.31-alpine-slim` upstream** (FG-073's pre-FG-079 plan) — would need `_EXPECTED=7 → 8` + a new upstream anchor, breaking the single-upstream-consumer invariant. Rejected now that FG-079's base/alpine-3 exists.
- **FROM scratch runtime without the scratch_base_alpine overlay** — the runtime's `ldd /usr/sbin/nginx` closure includes musl loader + libc + ssl/crypto/pcre libs + CA bundle. Putting all of those in `nginx-scratch-alpine`'s COPY directly works but bloats the image + leaks forge's "every scratch runtime overlays a base/scratch-*" convention. Rejected.

## Breaking changes

None public. Both are new images; no existing fleet image changes shape.

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI + local `make build && scan && verify` on both.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` → publishes both `base/scratch-alpine-3:3` + `nginx-scratch-alpine:latest` (publish-base → publish-derivatives ordering per FG-077 fix)
4. Verify tags via `docker manifest inspect`
5. Retire FG-073 draft (`docs/stories/FG-073-nginx-scratch-alpine.md`) — superseded.

## Tooling updates

| File | Change |
|---|---|
| `verify-dockerfile-conformance.py` | `_BASELINE` += `base/scratch-alpine-3`; `_KNOWN_REF_ARGS` += `BASE_SCRATCH_ALPINE_REF`; `_INTRA_LAYER_EXEMPTIONS` += `(base/scratch-alpine-3, base/alpine-3)` (L3 builder-stage FROMing another L3 — same pattern as base/python-slim-trixie → pre-builder/python-slim-trixie allowance). |
| `image_from_graph.py` | `_BASELINE` += `base/scratch-alpine-3` |
| `build-image.sh` | Add `BASE_SCRATCH_ALPINE_REF` resolver + build-arg + PULL_FLAG guard + _HAS_LOCAL_DEP check + on-demand builder. Extend `_needs_forge_builder` exclusion to include `base/scratch-alpine-3`. |

## Shipping evidence

Filled at pre-ship audit.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: base/scratch-alpine-3 exists + Rule 12 ✓ | `tests/acceptance/test_FG_080_*.sh:§1` | ✅ |
| Scenario: both build + smokes pass | test §2 | ✅ |
| Scenario: nginx serves HTTP 200 | `images/nginx-scratch-alpine/tests/smoke_serves_http.sh` | ✅ |
| Scenario: scratch-musl closure invariants | `images/base/scratch-alpine-3/tests/smoke_*.sh` | ✅ |
| Scenario: _EXPECTED stays at 7 | test §5 | ✅ |
| CAP `image.scratch-alpine-foundation` | test + CAPABILITIES | ✅ |
| CAP `image.nginx-scratch-alpine` | test + CAPABILITIES | ✅ |
