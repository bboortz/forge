*Dockerfile and build-time conventions for Forge images. Every image under `images/<name>/` conforms to this.*

## 7-tier layering model (FG-067)

Every Forge image belongs to exactly one tier, encoded by its directory prefix under `images/` (or flat position for L0 externals + L4 runtimes):

| Tier | Prefix | Role |
|------|--------|------|
| **L0** | — (external) | Upstream container images consumed by Forge (docker.io/*, ghcr.io/other-orgs/*) |
| **L0.1** | — (external) | Upstream source repos / release tarballs cloned-or-curled by Forge builds at build time |
| **L0.5** | `mirror/` | Forge-signed **zero-mod** passthroughs of external tool images (enforced by Rule 10) |
| **L1** | `pre-builder/` | Forge-signed thin variants of upstream OS bases: `apt-upgrade` + CA + `dumb-init` on top. Keeps shell + apt. |
| **L2** | `builder/` | Development toolchains for from-source compiles — **never runs in production**, only COPY-from target in multi-stage builds |
| **L3** | `base/` | Scratch-assembled runtime foundations consumed by other forge images (≥1 forge-internal consumer) |
| **L4** | — (flat) | Consumer-facing runtimes with **zero** forge-internal consumers. Includes apt-installed, from-source, and externally-sourced runtimes. |

Full definitions, 🔑 semantic tests, overlap-resolution matrix, decisions log: `docs/plan/tier-layering-model.md` §3 + §4 + §6.

**Rule 11** (`scripts/verify-dockerfile-conformance.py`, FG-067): the retired L4.5 `source/` tier must never resurface. Any `images/source/` directory fails lint. L4 absorbs from-source + externally-sourced runtimes; upstream source repos live at L0.1. Decision context: tier-layering-model.md §O8.

**L0.1 inventory** (`scripts/_upstream_sources.py`, FG-068): every upstream source repo / tarball URL referenced in Dockerfiles or `image.yaml source:` blocks is registered in `_UPSTREAM_SOURCES` with its declared consumers. `scripts/verify-source-inventory.py` enforces two-way sync (wired into `make test-fast`). The dep-graph emitter renders an L0.1 subgraph with dashed edges to each source's consumers. See `docs/plan/tier-layering-model.md` §10 for the current 10-entry inventory.

**Rule 12** (`scripts/verify-dockerfile-conformance.py`, FG-069): every `images/base/<name>/` L3 image must (a) have `FROM scratch` as its final-stage FROM AND (b) have at least one forge-internal consumer (another image's `image.yaml depends_on:` lists it). Zero-consumer base images belong at the flat L4 runtime position instead. Current members: `base/scratch-trixie` (9 consumers), `base/python-trixie` (3 consumers — beaconry-*). Renamed from `scratch-base-trixie` / `python-scratch-trixie` per tier-plan §O2+O3 (drop redundant tokens encoded by the tier prefix).

## Chain depth ≤ 5 (FG-042 invariant)

Deepest trust chains post-FG-072 (Python, Go, Zig all at the cap):

- Python: `debian:trixie-slim` → `python:3.14-slim-trixie` → `python-slim-trixie` → `forge-builder-python-trixie` → `scratch-base-trixie` → **5 hops** to a scratch runtime (e.g. `python-scratch-trixie`).
- Go:     `debian:trixie-slim` → `golang:1.27-trixie` → `go-slim-trixie` → `forge-builder-go-trixie` → `scratch-base-trixie` → **5 hops** to a scratch runtime (e.g. `node-exporter-scratch-trixie`).
- Node:   `debian:trixie-slim` → `node:24-trixie-slim` → `node-slim-trixie` → `forge-builder-node-trixie` → dual-builder scratch → **4 hops** to a scratch runtime (e.g. `prometheus-scratch-trixie`'s Node UI-builder stage; the Go chain via SBT reaches 5).
- Zig:    `debian:trixie-slim` → `debian-slim-trixie` → `zig-slim-trixie` → `forge-builder-zig-trixie` → (scratch runtime) — **5 hops** at cap. Zig's pre-builder FROMs the forge debian-slim-trixie instead of a Zig upstream (none exists on Docker Hub); documented tarball-install exception in `memory/design-decisions.md` § "Language family image pairs".

That's the ceiling.

Every added Forge pre-builder / builder / baseline tier deepens the chain for its downstream. Keep the cap at 5 unless a story explicitly justifies going deeper. Each extra layer is +~1 min of daily-cron time + an extra single-point-of-failure between the operator and the upstream distro.

If you find yourself adding a 6th tier, first ask: can this collapse into an existing tier? E.g. the three builder siblings (`forge-builder-python-trixie`, `forge-builder-go-trixie`, `forge-builder-node-trixie`) are each justified by their distinct upstream toolchain (python / go / node); do NOT add e.g. `forge-builder-rust-python-trixie` — add the Rust bits to an existing builder.

## Upstream Docker Hub anchor consumption (FG-042 + FG-065 invariant)

Every Docker Hub upstream used as a `FROM` line must be consumed by **exactly one** Forge image — the forge-rooted pre-builder for that family. Downstream slim / scratch images (including builders) FROM the forge image, not the upstream directly. Two reasons:

1. **Version drift prevention**: bumping an upstream version is a one-Dockerfile change (in the pre-builder) that propagates atomically; without this rule it's a multi-Dockerfile code-review-discipline task.
2. **Scanner / auditor surface reduction**: Beaconry + grype track one forge-signed base per family instead of multiple parallel-pulled upstream digests.

Enforced by `scripts/verify-no-upstream-drift.sh` (counts literal `^FROM <allowlisted upstream>` lines) + `scripts/verify-dockerfile-conformance.py` Rules 7+8+9 (per-image forge-over-upstream check, FG-065). Both wired into `make test-fast` + `make check`.

Current pre-builders (7): `debian-slim-trixie`, `debian-slim-sid`, `go-slim-trixie`, `node-slim-trixie`, `python-slim-trixie`, `ubuntu-slim-noble`, `zig-slim-trixie` (FG-072; tarball-install, FROMs `debian-slim-trixie` — doesn't bump `_EXPECTED`). Adding a new one with a Docker Hub upstream: edit `_UPSTREAM_ANCHORS` in the script + bump `_EXPECTED`; also update `_PRE_BUILDERS` in `discover-images.sh` + `verify-dockerfile-conformance.py` + `image_from_graph.py`; add the `<X>_REF` to `_KNOWN_REF_ARGS`. Adding a new tarball-install pre-builder (Zig precedent): same `_PRE_BUILDERS` + `_KNOWN_REF_ARGS` edits, no `_EXPECTED` bump, add a named entry to `_INTRA_LAYER_EXEMPTIONS`.

Exempt from this rule (post-FG-065):
- **Externally-maintained runtimes** (`postgres-slim-trixie` FROMs `postgres:18`): rebuilding from source is far bigger than the drift risk justifies. Explicitly allowlisted in `verify-dockerfile-conformance.py`'s `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS`.

The "dedicated-toolchain builder bases" exemption (FROMing `golang:1.27-trixie` / `node:24-trixie-slim` directly in the two forge-builders) was RETIRED by FG-065 — both forge-builders now dogfood their respective `<lang>-slim-trixie` pre-builders per the `arch.language-family-image-pair` invariant (see `memory/design-decisions.md`).

## Two-stage Dockerfile template (scratch runtime)

```dockerfile
# syntax=docker/dockerfile:1.7
ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

# Apply any sid pins committed under images/<name>/sid-pins/.
COPY sid-pins/ /etc/apt/preferences.d/
# shellcheck disable=SC2015
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Build-time additions go here (pip install, compile, strip, etc.).

# --- Stage 2: runtime ---------------------------------------------------------
FROM scratch AS runtime

# Interpreter + stdlib + libc + ld-linux. See § "What to COPY" below.
COPY --from=builder /usr/local/bin/python3.13     /usr/local/bin/python3.13
COPY --from=builder /usr/local/lib/python3.13     /usr/local/lib/python3.13
COPY --from=builder /lib/x86_64-linux-gnu/libc.so.6         /lib/x86_64-linux-gnu/libc.so.6
COPY --from=builder /lib/x86_64-linux-gnu/libssl.so.3       /lib/x86_64-linux-gnu/libssl.so.3
COPY --from=builder /lib/x86_64-linux-gnu/libcrypto.so.3    /lib/x86_64-linux-gnu/libcrypto.so.3
COPY --from=builder /lib/x86_64-linux-gnu/libm.so.6         /lib/x86_64-linux-gnu/libm.so.6
COPY --from=builder /lib/x86_64-linux-gnu/libpthread.so.0   /lib/x86_64-linux-gnu/libpthread.so.0
COPY --from=builder /lib/x86_64-linux-gnu/libdl.so.2        /lib/x86_64-linux-gnu/libdl.so.2
COPY --from=builder /lib64/ld-linux-x86-64.so.2             /lib64/ld-linux-x86-64.so.2
# Also COPY /etc/ssl/certs/ca-certificates.crt for TLS.

ENTRYPOINT ["/usr/local/bin/python3.13"]
```

Multi-arch note: the `/lib/<triple>` path is per-arch (`aarch64-linux-gnu` on arm64). Use buildx `TARGETARCH` + a sed step, or publish per-arch Dockerfiles — do not hard-code x86_64 in the image we publish for arm64.

## What to COPY into the scratch stage — discovery recipe

Reproduce this inside the builder stage once per image, then commit the discovered paths:

```bash
# everything the interpreter dlopens
ldd /usr/local/bin/python3.13 | awk '/=>/ {print $3}'

# everything stdlib modules dlopen under /usr/local/lib/python3.13/lib-dynload/
find /usr/local/lib/python3.13/lib-dynload -name '*.so' -exec ldd {} \; \
  | awk '/=>/ {print $3}' | sort -u

# CA bundle (empty curl / urllib without this)
/etc/ssl/certs/ca-certificates.crt

# zoneinfo if the image handles timezone-sensitive data
/usr/share/zoneinfo
```

Rule: if `ldd` says it's needed, it must be COPY'd. If it isn't needed, do not COPY "just in case" — the point of scratch is a tight runtime.

## sid-pin file format

Under `images/<name>/sid-pins/<package>.pref`:

```
# CVE-2026-NNNNN: libxml2 double-free in SAX2 path.
# Backport to trixie not landed as of 2026-11-03. Remove this pin once
# libxml2 ≥ 2.12.9+dfsg-1 is in trixie.
Package: libxml2
Pin: release a=unstable
Pin-Priority: 500
```

Required fields in the comment: CVE id, condition for removal, date added. `make verify-sid-pins` greps these; a pin with no removal condition fails lint.

## Multi-arch builds

Primary platforms: `linux/amd64`, `linux/arm64`. We build via `docker buildx build --platform linux/amd64,linux/arm64 --push`. GHA runners emulate arm64 via QEMU, which is slow but acceptable at daily cadence. If build time crosses ~45 min we migrate arm64 to a `ubuntu-22.04-arm` runner.

## Build cache

- Use `--cache-from=type=registry,ref=ghcr.io/bboortz/<name>:buildcache` and `--cache-to=type=registry,ref=...,mode=max` on both PR and nightly builds.
- Cache invalidation is implicit when a sid pin changes (apt layer rehashes) — do not add cache-busting ARGs.

## Image labels

Every image sets, at minimum:

```dockerfile
LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched <name> base image"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
```

`revision` + `created` are injected at build time via `--label` from the Makefile — do not hard-code in the Dockerfile.

## Per-image smoke tests (`images/<name>/tests/`)

Every image under `images/<name>/` owns a `tests/` dir of smoke scripts that encode its contract — what it must still do after any `apt upgrade`, sid pin, or runtime-shape change. Scripts are co-located so `images/<name>/` stays self-contained: `Dockerfile` + `build.sh` + `sid-pins/` + `tests/`.

Convention:

- Each script is `images/<name>/tests/smoke_<thing>.sh`, executable, `set -euo pipefail`, shellcheck-clean.
- Each reads `${IMAGE_NAME}`, `${IMAGE_TAG}`, `${REGISTRY}` from env (defaults are fine for local invocation).
- Scripts are independently runnable (`bash images/<name>/tests/smoke_<thing>.sh`) AND discoverable (`make test-images` globs them).
- The Makefile `test-images` target scopes with `IMAGE_NAME=<name>` or runs every image's suite.

Baseline every new image provides (minimum):

- `smoke_imports.sh` (or the language's equivalent "core features load") — fails if a stdlib / core lib was lost in a rebuild.
- `smoke_tls_handshake.sh` + `smoke_ca_bundle.sh` — any image that will make outbound HTTPS calls must prove the CA path works.
- `smoke_entrypoint.sh` — exercises the documented invocation pattern (python3 for python; `nginx -t` for nginx; `postgres --version` for postgres).
- `smoke_size.sh` — image size ≤ **upstream base × 1.1** (10% headroom for apt-upgrade). The base is parsed from the Dockerfile's `FROM` line so a future base-bump auto-updates the ceiling.

Scratch-runtime variants (FG-003+) use the **same** smoke suite as the slim variant that preceded them. If a scratch image can't pass every assertion its slim predecessor passes, the ldd closure is wrong — the suite is the oracle.

## What NOT to put in a Forge image

- Shell (`sh`, `bash`, `busybox`) in a scratch-runtime image. The `-slim` variants keep their shell on purpose; scratch runtimes do not.
- Package managers (`apt`, `apk`, `pip`) in the runtime stage.
- Compilers, build toolchains, header files, docs, `.pyc` cache directories (`__pycache__`).
- `/tmp` content from the builder (strip it with `rm -rf` before the final COPY surface).

If you catch yourself COPY'ing a directory and only using 2% of it, extract the 2%.
