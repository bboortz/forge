---
id: FG-080
slug: nginx-scratch-alpine-and-scratch-alpine-base
status: draft
owner: bboortz
created: 2026-11-21
---

# FG-080 — `base/scratch-alpine-3` + `nginx-scratch-alpine` (atomic pair)

Two new images shipped together. First Alpine-musl scratch runtime in the fleet, closing the "forge has scratch runtimes but only for glibc" gap. Supersedes the long-draft FG-073 (`nginx-scratch-alpine`) by pairing it with the musl scratch overlay it needs. Must land together — Rule 12 requires L3 `base/*` to have ≥1 forge-internal consumer.

## Why pair base + runtime in one FG

Rule 12 (post-FG-075) accepts shape-agnostic L3 images but still enforces the invariant "every `base/*` has ≥1 forge-internal consumer." Shipping `base/scratch-alpine-3` alone would create a lint failure; shipping `nginx-scratch-alpine` alone would force it to assemble the musl closure inline (no overlay deduplication). Atomic pair gives both:

- `base/scratch-alpine-3` — musl + CA + nss + /etc + zoneinfo scratch overlay
- `nginx-scratch-alpine` — first consumer (nginx apk-sourced, dropped into scratch)

## 9 canonical answers

1. **Who** — Forge maintainers (new L3 overlay to maintain); nginx consumers (homelab's TLS-termination layer today lives in forge's glibc `nginx-scratch-trixie`; some deployments may prefer the sub-10 MB Alpine variant); FG-073's long-held draft, finally landing.
2. **When** — Fires every time a consumer needs a scratch-musl runtime. Today: no forge image fits. After FG-080: nginx-scratch-alpine + any future scratch-musl runtime (haproxy, dnsmasq, etc.) overlays base/scratch-alpine-3.
3. **What success looks like** —
   - `images/base/scratch-alpine-3/` published at `ghcr.io/bboortz/base/scratch-alpine-3:3`. `FROM scratch` runtime stage (Rule 12 ✓). Shipped closure: musl loader + libc + ca-certs + nss + /etc/{passwd,group,nsswitch.conf,resolv.conf,hosts} + /usr/share/zoneinfo/UTC. Nonroot uid 65532 entry in /etc/passwd.
   - `images/nginx-scratch-alpine/` published at `ghcr.io/bboortz/nginx-scratch-alpine:latest`. Builder stage FROM `base/alpine-3` + `apk add nginx` → COPY nginx binary + modules to scratch runtime. Runtime stage: `FROM scratch` + `COPY --from=scratch_base_alpine / /` overlay + `COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx`. VOLUME /var/cache/nginx + /var/log/nginx. EXPOSE 80 + 443. HEALTHCHECK via /hc.
   - Rule 12 satisfied: `base/scratch-alpine-3` has ≥1 consumer (nginx-scratch-alpine).
   - `_EXPECTED=7` unchanged (neither image FROMs upstream — base/scratch-alpine-3 FROMs scratch; nginx-scratch-alpine FROMs scratch + its builder FROMs base/alpine-3).
   - Chain depth for nginx-scratch-alpine runtime stage: `scratch` = 0 hops. Build-time chain via base/alpine-3 = 4 hops (alpine:3 → pre-builder/alpine-3 → base/alpine-3). Scratch overlay via COPY-from base/scratch-alpine-3 (not a FROM-hop).
4. **Urgency** — Quality-of-life. Moderate: FG-073 has been draft for weeks; homelab or external consumer may want sub-10 MB nginx. No CVE pressure.
5. **Happy path** —
   1. Create `images/base/scratch-alpine-3/` — 2-stage Dockerfile: builder FROM `${BASE_ALPINE_REF}` + apk-add musl + ca-certificates + build /etc stubs → scratch runtime + COPY curated closure.
   2. Create `images/nginx-scratch-alpine/` — 3-stage Dockerfile: scratch_base FROM `${BASE_SCRATCH_ALPINE_REF}`, builder FROM `${BASE_ALPINE_REF}` + `apk add nginx` + stage binary + modules, runtime FROM scratch + overlay + COPY.
   3. Smoke tests per image (scratch-overlay invariants for the base, HTTP 200 serves for nginx).
   4. Tooling updates: `_BASELINE` += `base/scratch-alpine-3`; `_KNOWN_REF_ARGS` += `BASE_SCRATCH_ALPINE_REF`; build-image.sh BASE_SCRATCH_ALPINE_REF resolver. Register nginx-scratch-alpine depends_on + EXPECTATIONS vs base/scratch-alpine-3.
   5. Dep graph regen + CAPs + `make test-fast`.
   6. PR + CI + merge + release + publish.
6. **Edge cases / failure modes** —
   - **musl closure completeness**: unlike glibc, musl's loader (`/lib/ld-musl-x86_64.so.1`) is a symlink into `/lib/libc.musl-x86_64.so.1` on Alpine. Must COPY both via `cp -a` (preserve symlinks per `memory/scratch-closures.md`). Verify via `ldd /usr/sbin/nginx` ldd-closure inside the builder.
   - **nginx config shape**: upstream Alpine's `nginx` package includes a default config that references `conf.d/`, `modules/`, `/var/log/nginx/`, `/var/cache/nginx/` sub-trees. Need to pre-create those dirs in the builder stage with 65532 ownership (scratch has no mkdir at runtime). Mirrors the `memory/scratch-closures.md` nginx-scratch-trixie lesson.
   - **TLS stack**: Alpine's nginx dynamically links OpenSSL from `libssl.so.3` + `libcrypto.so.3`. Include both in the builder COPY list.
   - **Rule 12 timing**: base/scratch-alpine-3 must have its consumer (nginx-scratch-alpine) exist in the same commit or Rule 12 fires in isolation. Atomic PR handles.
   - **Alpine point-release drift**: `base/alpine-3` floats on `alpine:3`. If Alpine 3.22 ships with a nginx version bump, nginx-scratch-alpine rebuilds against the new one via daily cron automatically. No scan-baseline drift surprise beyond the normal apk-package delta.
   - **No HTTP/3 (quic)**: Alpine's nginx package doesn't enable `--with-http_v3_module` by default. Document in PROMISES; consumers needing QUIC build from source (future FG, not here).
7. **Out of scope** —
   - `base/python-scratch-alpine-3` or any from-musl-source language scratch overlay. Separate FG per language.
   - Migrating `nginx-scratch-trixie` consumers to `nginx-scratch-alpine`. Both ship as siblings; operators pick.
   - QUIC / HTTP/3 support.
   - nginx stream module (ssl_preread / L4 proxy). FG-016 shipped it for the trixie variant; Alpine's package may or may not include it — audit at implementation time, flag in story if absent.
   - Multi-arch (amd64 only).
   - No homelab migration — separate paired PR if homelab wants to adopt the alpine variant.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_080_nginx-scratch-alpine-and-scratch-alpine-base.sh`. Both images build + smokes pass locally; both tags live on GHCR after publish; nginx-scratch-alpine starts + serves HTTP 200 on `/`; dep graph shows base/scratch-alpine-3 in L3 + nginx-scratch-alpine in L4 with overlay edge.
9. **Capabilities delivered or extended** —
   - NEW `image.scratch-alpine-foundation` — `base/scratch-alpine-3` scratch-musl overlay (parallel to `arch.base-tier-images` for scratch-glibc `base/scratch-trixie`).
   - NEW `image.nginx-scratch-alpine` — sub-10 MB nginx on musl.
   - EXT `arch.base-tier-public-api` — scratch-alpine joins the base/* tier.

## Design — base/scratch-alpine-3 closure

Parallel to `base/scratch-trixie`'s strict-intersection shape (per `memory/scratch-closures.md`):

| Path | Source | Purpose |
|---|---|---|
| `/lib/ld-musl-x86_64.so.1` | apk `musl` | musl dynamic loader (symlink target preserved via `cp -a`) |
| `/lib/libc.musl-x86_64.so.1` | apk `musl` | musl C library |
| `/etc/ssl/certs/ca-certificates.crt` | apk `ca-certificates` | TLS trust store (required by `arch.base-tier-public-api`) |
| `/etc/nsswitch.conf` | manual (minimal) | nss resolution policy (required for getaddrinfo) |
| `/etc/passwd` | manual | root + nobody + 65532 entries |
| `/etc/group` | manual | root + nogroup entries |
| `/etc/hosts` | manual | localhost + ::1 stubs |
| `/etc/resolv.conf` | empty placeholder | docker runtime overlays this at launch |
| `/usr/share/zoneinfo/UTC` | apk `tzdata` | minimal timezone (24 KB; consumers that need more mount /etc/localtime) |

Rule 12 compliance: `base/scratch-alpine-3` FROMs scratch for its final stage + nginx-scratch-alpine depends_on it in this same PR.

## Design — nginx-scratch-alpine builder + runtime

Shape mirrors `nginx-scratch-trixie` (FG-006) + `memory/scratch-closures.md` recipe:

```
# Stage 0: scratch overlay reference
FROM ${BASE_SCRATCH_ALPINE_REF} AS scratch_base_alpine

# Stage 1: nginx builder (apk source)
FROM ${BASE_ALPINE_REF} AS builder
USER 0
RUN apk add --no-cache nginx
# Stage nginx + modules + required dynamic libs into /out layout
RUN mkdir -p /out/usr/sbin /out/usr/lib/nginx/modules /out/var/cache/nginx /out/var/log/nginx /out/etc/nginx \
 && cp /usr/sbin/nginx /out/usr/sbin/nginx \
 && cp -a /usr/lib/nginx/modules/* /out/usr/lib/nginx/modules/ \
 && ldd /usr/sbin/nginx | awk '/=>/ {print $3}' | while read -r lib; do \
      mkdir -p "/out$(dirname "$lib")" && cp "$lib" "/out$lib"; \
    done \
 && cp -r /etc/nginx/* /out/etc/nginx/ \
 && chown -R 65532:65532 /out/var/cache/nginx /out/var/log/nginx

# Stage 2: SBOM
FROM ${BASE_ALPINE_REF} AS sbom
USER 0
COPY --from=builder /out /sbom-input
COPY --from=mirror/syft /syft /usr/local/bin/syft
RUN syft dir:/sbom-input -o cyclonedx-json > /sbom.json

# Stage 3: hc
FROM ${HC_REF} AS hc

# Stage 4: runtime (scratch + musl overlay + nginx)
FROM scratch AS runtime
COPY --from=scratch_base_alpine / /
COPY --from=builder /out /
COPY --from=sbom /sbom.json /sbom.json
COPY --from=hc /hc /hc
USER 65532
EXPOSE 80 443
VOLUME ["/var/cache/nginx", "/var/log/nginx"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1/"]
ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]
```

## Chain depth

- `nginx-scratch-alpine` runtime FROM: `scratch` → 0 hops
- Build-time FROM: `alpine:3 → pre-builder/alpine-3 → base/alpine-3` → 3 hops to builder (discarded at runtime)
- Overlay (COPY-from): `base/scratch-alpine-3` (built from `base/alpine-3` + staged closure to scratch) — overlay edges don't count toward the FG-042 hop cap

All well under FG-042's 5-hop cap.

## Tooling updates

| File | Change |
|---|---|
| `scripts/verify-dockerfile-conformance.py` | `_BASELINE` += `base/scratch-alpine-3`; `_KNOWN_REF_ARGS` += `BASE_SCRATCH_ALPINE_REF` |
| `scripts/image_from_graph.py` | `_BASELINE` list grows |
| `scripts/build-image.sh` | Add `BASE_SCRATCH_ALPINE_REF` resolver + build-arg + PULL_FLAG guards + _HAS_LOCAL_DEP check + on-demand builder |

## Gherkin acceptance

```
Scenario: base/scratch-alpine-3 exists + Rule 12 satisfied
  Given FG-080 has shipped
  Then images/base/scratch-alpine-3/Dockerfile FROMs scratch for its final stage
   And at least one images/*/image.yaml declares depends_on base/scratch-alpine-3
   And verify-dockerfile-conformance.py exits 0 (Rule 12 ✓)

Scenario: both images build + smokes pass
  Given FG-080 has shipped
  When I run bash scripts/build-image.sh base/scratch-alpine-3
   And bash scripts/build-image.sh nginx-scratch-alpine
  Then both succeed
   And every smoke script under tests/ exits 0

Scenario: nginx-scratch-alpine serves HTTP 200
  Given FG-080 has shipped + nginx-scratch-alpine built
  When I `docker run -d -p 80:80 forge-local/nginx-scratch-alpine:latest` + curl :80/
  Then I get HTTP 200 (or the nginx default page)

Scenario: scratch-musl closure invariants
  Given FG-080 has shipped
  When I probe base/scratch-alpine-3
  Then /lib/ld-musl-x86_64.so.1 + /lib/libc.musl-x86_64.so.1 are present
   And /etc/ssl/certs/ca-certificates.crt is non-empty
   And /etc/passwd has entries for root + 65532
   And nginx-scratch-alpine inherits all of the above via COPY --from= overlay

Scenario: _EXPECTED stays at 7
  Given FG-080 has shipped
  Then verify-no-upstream-drift.sh _EXPECTED=7 (unchanged — neither image FROMs upstream)
```

## References

- Parent: FG-079 `base/alpine-3` + `pre-builder/alpine-3` (shipped 2026-11-21)
- Supersedes: FG-073 draft (`nginx-scratch-alpine` — pre-FG-079 the plan was to FROM `nginx:1.31-alpine-slim` directly; now rebuilds on base/alpine-3)
- Pattern precedent: `base/scratch-trixie` + `nginx-scratch-trixie` (FG-005 + FG-006); scratch-closure guidance in `memory/scratch-closures.md`
- Plan: `docs/plan/FG-080-*-plan.md` (to be created at ready state)
- Red test: `tests/acceptance/test_FG_080_nginx-scratch-alpine-and-scratch-alpine-base.sh`
