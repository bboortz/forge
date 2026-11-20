---
id: FG-073
slug: nginx-scratch-alpine
status: draft
owner: bboortz
created: 2026-11-20
---

# FG-073 — `nginx-scratch-alpine` (first Alpine-based Forge image, nginx 1.31.9 mainline)

Operators who want **nginx 1.31.9 mainline** — a release Debian trixie won't carry for many months — get a forge-signed scratch runtime built against upstream nginx's own Alpine image. The existing `nginx-scratch-trixie:1.26` (Debian stable channel) stays published and continues to receive the usual daily-cron treatment; `nginx-scratch-alpine:1.31.9` lives alongside it as the mainline-tracking variant. This is also the first forge image built on an Alpine base — a third documented exception to the "Debian trixie" rule (alongside Ubuntu for FG-051 + Debian sid for FG-058).

## 9 canonical answers

1. **Who** — Ops / platform engineer operating a homelab or edge deployment who needs an nginx feature only available in mainline (HTTP/3 refinements, QUIC tuning knobs, new `ssl_preread`/`stream` directives, specific CVE fixes that haven't backported to 1.26) AND is willing to trade stable's conservative release lifecycle for feature access. Also the Forge maintainer validating that an Alpine-based scratch image is viable + scanner-tractable.

2. **When** — Fires on every daily cron (publishes alongside `nginx-scratch-trixie:1.26`). Also fires when:
   - Upstream nginx cuts a new mainline release — a chore commit bumps `ARG NGINX_ALPINE_TAG=1.31.<new>-alpine-slim` + SHA256 pin.
   - A CVE lands against mainline that stable doesn't carry (or vice versa).
   - An Alpine SecDB advisory lands against the shipped musl/openssl/pcre closure.

3. **What success looks like**:
   - `ghcr.io/bboortz/nginx-scratch-alpine:1.31.9` + `:latest` (and their `-amd64` arch aliases) published, cosign-signed, with scan + SBOM attestations.
   - `docker run --rm -p 8080:80 ghcr.io/bboortz/nginx-scratch-alpine:1.31.9` serves HTTP 200 on `/` with nginx default welcome page.
   - `docker run ... nginx -v` prints `nginx version: nginx/1.31.9`.
   - Image size ≤ **12 MB** (Alpine's musl + minimal pcre2/openssl/zlib closure + nginx binary — vastly smaller than the Debian-based `nginx-scratch-trixie` at ~15 MB because musl is slimmer than glibc).
   - `grype` scan uses the Alpine `apk` matcher (new for forge) and runs clean or with explicit baselined CVEs.
   - `cosign verify --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml ghcr.io/bboortz/nginx-scratch-alpine:1.31.9` exits 0.
   - `make test-fast` + `make check` green on dev.
   - `memory/design-decisions.md` § "Exception — Alpine" documents the third case-by-case base-family exception.

4. **Urgency** — Quality-of-life / feature-access. Not security-critical today; `nginx-scratch-trixie:1.26.3-deb13uN` tracks trixie-security and is the recommended default. FG-073 opens the mainline channel for operators who explicitly ask for it.

5. **Happy path**:
   1. Branch `feat/FG-073-nginx-scratch-alpine` from `dev`; create plan doc.
   2. Red acceptance test `tests/acceptance/test_FG_073_nginx-scratch-alpine.sh` — asserts: directory layout, Dockerfile FROMs the pinned `nginx:1.31.9-alpine-slim` with committed SHA256, builder stage assembles overlay into `/out`, runtime is `FROM scratch` with only COPY from the builder, nginx binary + musl closure present, HTTP 200 on `/`, image size ≤ 12 MB, scan + cosign verify succeed.
   3. Create `images/nginx-scratch-alpine/`:
      - `Dockerfile`: builder stage `FROM nginx:1.31.9-alpine-slim AS builder`; assembles `/out/{usr/sbin/nginx, lib/*.so, etc/ssl/certs/ca-certificates.crt, etc/passwd, etc/group, etc/nginx/, var/log/nginx, var/cache/nginx, var/lib/nginx/*, usr/share/nginx/html}` with correct ownership (nginx user from upstream Alpine image). Runtime `FROM scratch`, `COPY --from=builder /out /`, `ENTRYPOINT ["/usr/sbin/nginx"]`, `CMD ["-g", "daemon off;"]`, `EXPOSE 80`.
      - `image.yaml`: `tag: "1.31.9"`, `platforms: [linux/amd64]`, no `depends_on` (no Forge-local parents — the one Alpine upstream parent is pinned in the Dockerfile).
      - `PROMISES.yaml`: see § 9.
      - `scan-baseline.json`: initial state, likely empty critical_cves on first publish.
      - `sid-pins/.gitkeep` (unused — kept for layout symmetry; Alpine has no sid concept).
      - `tests/smoke_*.sh`: `smoke_serves_200.sh`, `smoke_nginx_version.sh`, `smoke_no_shell.sh`, `smoke_ca_bundle.sh`, `smoke_size.sh`, `smoke_zero_dpkg.sh` (asserts no `/var/lib/dpkg` — this is Alpine-based, not Debian).
   4. Update `scripts/verify-dockerfile-conformance.py`: add `nginx:1.31.9-alpine-slim` → `nginx-scratch-alpine` to `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS` (same pattern used for postgres-slim-trixie → `postgres:18`); add `nginx:1.31.9-alpine-slim` to `_UPSTREAM_ALLOWLIST`.
   5. `scripts/verify-no-upstream-drift.sh`: do NOT add `nginx:...-alpine-slim` to `_UPSTREAM_ANCHORS`. Rationale: that script counts upstreams that each SHOULD be consumed by exactly one forge pre-builder. `nginx:1.31.9-alpine-slim` is a specific-purpose runtime image (not a generic OS base), consumed by exactly one derivative (nginx-scratch-alpine), and doesn't need a pre-builder intermediate. Same category as `postgres:18`. `_EXPECTED` stays at 6.
   6. Update `memory/design-decisions.md`: new § "Exception — Alpine (FG-073, 2026-11-20)" alongside Ubuntu + sid exceptions.
   7. `scripts/image_from_graph.py`: no code change needed — the dep graph will auto-pick up the new image when `nginx:1.31.9-alpine-slim` is added as a known upstream. Add a node definition to `_UPSTREAM_NODE_IDS` for the new Alpine anchor.
   8. `scripts/discover-images.sh`: zero changes — `nginx-scratch-alpine` is a derivative with no deps, so it falls under either `base` or `derivatives` mode automatically.
   9. `make dep-graph` regenerates docs/image-dependency-graph.{md,svg} showing: `UP_NGINX_ALPINE → nginx-scratch-alpine` (new L4 node, solid edge).
   10. `docs/CAPABILITIES.md`: NEW `build.nginx-mainline-alpine` + EXT `image.nginx-serves-http`. Update `test.smoke-server-helper` consumers list.
   11. Docker Hub rate limit considerations: the builder stage pulls `nginx:1.31.9-alpine-slim` — one more public pull for daily cron. Within quota; no auth change needed.
   12. PR → CI → auto-merge → next 03:00 UTC cron publishes.

6. **Edge cases / failure modes**:
   - **musl vs glibc**: nginx-scratch-alpine's nginx binary is musl-linked. Operators running this image never execute arbitrary code inside it — there's no shell — so musl/glibc ABI difference is invisible to consumers. Documented in PROMISES: this image's binary uses musl, not glibc.
   - **CA bundle format**: Alpine ships `/etc/ssl/certs/ca-certificates.crt` (same path as Debian, but generated by `ca-certificates`'s Alpine package). Downstream nginx configs that reference `ssl_trusted_certificate` still just work.
   - **nginx user UID mismatch**: upstream `nginx:alpine` creates user `nginx` with uid 101; `nginx-scratch-trixie`'s www-data is uid 33. Documented delta — operators who mount volumes expecting one uid get surprised when switching. Call out in the PROMISES `presence.service-user` entry + the README comparison section.
   - **No `nginx -t` without config**: the scratch runtime ships only the default `nginx.conf`. Operators mount their own config; `nginx -t` works against the mounted file.
   - **Modules**: upstream nginx:1.31.9-alpine-slim ships with the stream module compiled in (parity with Debian's `libnginx-mod-stream` that `nginx-scratch-trixie` apt-installs). Verified in smoke.
   - **Alpine SecDB scanner coverage**: grype detects the image as Alpine (via the `apk` DB that we DON'T ship — but syft's binary cataloger picks up nginx + openssl + pcre + zlib versions directly from the ELF). Either (a) include `/lib/apk/db/installed` in the overlay so apk-matcher works, or (b) rely on the binary cataloger. Decision deferred to the plan doc — leaning (a) because it gives Beaconry consistent upstream advisory data.
   - **Image-size budget**: 12 MB is aggressive. If the overlay grows (e.g. additional module needed), the budget needs to bump. Smoke `smoke_size.sh` asserts the cap.
   - **No sidecar-init needed**: nginx needs no first-boot init (unlike postgres' `initdb`). Direct `docker run` works.
   - **hc healthcheck binary**: `/hc` (per FG-031) is currently glibc-linked (compiled against Debian trixie by hc's own build). It would NOT run in a musl-only scratch runtime without a static-musl rebuild. **Decision**: do NOT bake `/hc` into nginx-scratch-alpine for V1. Operators who need a healthcheck mount an external checker or use `wget --spider` from the host. The FG-072 hc-migration follow-up (static Zig rebuild) can later provide a musl-compat `/hc` and we revisit.

7. **Out of scope**:
   - **Replacing `nginx-scratch-trixie`** — both coexist. Operators pick based on feature-track preference (stable = trixie, mainline = alpine). Documented in README.
   - **nginx-scratch-alpine with HTTP/3 enabled** — upstream's `-alpine` image has http_v3 compiled; verify in smoke but don't advertise as a featured capability yet.
   - **Per-module variants** (otel, perl) — the official nginx-mainline image has `-alpine-otel`, `-alpine-perl`, `-alpine-slim` variants; FG-073 uses `-alpine-slim` only. Variants are separate FGs if operators ask.
   - **`alpine-slim-<ver>` generic Forge pre-builder** — not needed for a single consumer; parallel to how `postgres:18` is consumed without a Debian-postgres pre-builder. When a 2nd Alpine consumer lands, revisit the Alpine pre-builder question (parallel to the FG-042 journey for Debian).
   - **`nginx-slim-alpine`** (shelled Alpine variant) — the whole point of this image is minimal. If operators want a shelled nginx-alpine, they can use `nginx:1.31.9-alpine-slim` directly; Forge adds no value there.
   - **Changing cosign identity / verification URL** — FG-073 inherits the standard forge pipeline.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.nginx-mainline-alpine` — forge-signed scratch runtime built from upstream `nginx:1.31.9-alpine-slim`. Serves HTTP on port 80, ships default `nginx.conf` + default welcome page, nginx user uid 101 (matches upstream Alpine convention), size ≤ 12 MB. Scanner coverage via grype's Alpine `apk` matcher (shipping the apk DB in the overlay) + syft binary cataloger.
   - NEW `arch.alpine-base-exception` — third case-by-case base-family exception (after FG-051 Ubuntu + FG-058 Debian sid). Documents the policy for Alpine-based Forge images: specific-purpose feature tracking (mainline access, musl-small-closure wins), scanner coverage via `apk` matcher, single-consumer-per-upstream still enforced (nginx-alpine upstream consumed by one derivative).
   - EXT `image.nginx-serves-http` — second nginx image joining `nginx-scratch-trixie` as a satisfying consumer. Contract symmetric: both serve HTTP 200 + run as nonroot nginx user + no shell + reload on SIGHUP.
   - EXT `test.smoke-server-helper` — adds `nginx-scratch-alpine` as a new consumer of `scripts/smoke-server.sh` (parallel to `nginx-scratch-trixie`, `postgres-scratch-trixie`, `redis-scratch-trixie`, etc.).

## Gherkin acceptance

```
Scenario: images/nginx-scratch-alpine/ exists with the standard scratch-runtime layout
  Given current HEAD
  Then images/nginx-scratch-alpine/{Dockerfile, image.yaml, PROMISES.yaml,
       scan-baseline.json, tests/smoke_*.sh} all exist
  And image.yaml declares tag: "1.31.9" and platforms: [linux/amd64]
  And image.yaml has NO depends_on (no Forge-local parents)

Scenario: Dockerfile FROMs the pinned Alpine upstream + has a scratch runtime
  Given images/nginx-scratch-alpine/Dockerfile
  Then it declares `FROM nginx:1.31.9-alpine-slim AS builder`
  And the final stage is `FROM scratch`
  And it does NOT COPY --from=scratch_base (Debian baseline is glibc — incompatible)
  And it has an `ARG NGINX_ALPINE_SHA256=` committed pin for the upstream tag

Scenario: nginx binary serves HTTP 200 on the default route
  Given forge-local/nginx-scratch-alpine:1.31.9 built
  When `scripts/smoke-server.sh` starts the container with `-p 0:80`
  And `curl -sS http://127.0.0.1:<port>/` runs
  Then the response is HTTP 200
   And the body contains "Welcome to nginx"

Scenario: nginx reports version 1.31.9 mainline
  Given forge-local/nginx-scratch-alpine:1.31.9 built
  When `docker run --rm --entrypoint=/usr/sbin/nginx forge-local/nginx-scratch-alpine:1.31.9 -v` runs
  Then stderr contains "nginx version: nginx/1.31.9"

Scenario: scratch runtime has no shell
  Given forge-local/nginx-scratch-alpine:1.31.9 built
  When `docker save` is piped into the layer walker
  Then no layer contains /bin/sh, /bin/bash, /bin/ash, or /bin/busybox
   And no layer contains /usr/bin/apk (Alpine package manager not shipped)

Scenario: image size ≤ 12 MB
  Given forge-local/nginx-scratch-alpine:1.31.9 built
  When `docker image inspect` reports Size
  Then Size is ≤ 12582912 bytes (12 MiB)

Scenario: CA bundle present for outbound TLS (nginx upstream https:// configs)
  Given forge-local/nginx-scratch-alpine:1.31.9 built
  Then /etc/ssl/certs/ca-certificates.crt is present and non-empty

Scenario: Dockerfile conformance lint accepts the new upstream
  Given scripts/verify-dockerfile-conformance.py
  Then `nginx:1.31.9-alpine-slim` is in `_UPSTREAM_ALLOWLIST`
  And `nginx-scratch-alpine` maps to `nginx:1.31.9-alpine-slim` in `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS`
  And the lint passes against current HEAD

Scenario: verify-no-upstream-drift _EXPECTED stays at 6
  Given scripts/verify-no-upstream-drift.sh
  Then `_EXPECTED=6` (unchanged — nginx:*-alpine-slim is not a generic OS base
       anchor; same category as postgres:18)
  And the drift guard exits 0

Scenario: memory/design-decisions.md documents the Alpine exception
  Given memory/design-decisions.md
  Then a "### Exception — Alpine (FG-073, ...)" section exists
  And lists: (1) rationale (musl-small-closure wins for feature-tracking images);
      (2) scanner coverage note (apk matcher + syft binary cataloger);
      (3) policy — single-consumer-per-upstream still enforced;
      (4) current satisfying images list (nginx-scratch-alpine)

Scenario: cosign verify succeeds against the public identity
  Given ghcr.io/bboortz/nginx-scratch-alpine:1.31.9 (post-publish)
  When `cosign verify --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml --certificate-oidc-issuer https://token.actions.githubusercontent.com <image>` runs
  Then it exits 0

Scenario: dep graph shows the new Alpine edge
  Given regenerated docs/image-dependency-graph.md
  Then the mermaid contains `UP_NGINX_ALPINE --> nginx-scratch-alpine`
  And `nginx-scratch-alpine` appears under the L4 runtimes subgraph
  And no edge to scratch-base-trixie exists (musl/glibc split)
```

## References

- Plan: `docs/plan/FG-073-nginx-scratch-alpine-plan.md` (follow-up)
- Red test: `tests/acceptance/test_FG_073_nginx-scratch-alpine.sh` (follow-up)
- Pattern precedent:
  - FG-006 (`nginx-scratch-trixie` — scratch runtime shape to mirror)
  - FG-007 (`postgres-scratch-trixie` — specific-purpose upstream consumed directly, `postgres:18` in `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS`)
  - FG-051 (Ubuntu — first case-by-case base-family exception) + FG-058 (Debian sid — second)
- Related invariants + memory docs:
  - `memory/design-decisions.md` § "Base distribution — Debian trixie" (will add § "Exception — Alpine (FG-073)")
  - `memory/docker-standard.md` § "Upstream Docker Hub anchor consumption" (nginx:alpine joins postgres:18 as a specific-purpose runtime exemption)
  - `memory/scratch-closures.md` (ldd closure recipe — for Alpine this is `ldd` against musl-linked binaries; same approach, different library paths)
- Design choices:
  - **No `scratch-base-trixie` overlay** — the Debian baseline ships glibc; musl-linked nginx can't use it. nginx-scratch-alpine builds its own minimal overlay (musl + CA + passwd/group).
  - **No `/hc` healthcheck** — current hc binary is glibc-linked. Revisit when FG-072's follow-up ships a musl-compat `/hc`.
  - **Mainline, not stable** — operator-explicit choice; nginx-scratch-trixie continues to cover the stable track.
