# Forge scratch baseline — contract

**Image**: `ghcr.io/bboortz/scratch-base-trixie`
**Current version**: `0.2` (also published as `:latest`)
**Verify identity**: `https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main`

This document is the audit surface for every Forge scratch image. Every derivative composes by `COPY --from=ghcr.io/bboortz/scratch-base-trixie:latest / /` on top of `FROM scratch`, so the guarantees below hold for python-scratch-trixie, nginx-scratch-trixie, postgres-scratch-trixie, and every future scratch variant automatically.

## File-layout API (guaranteed to exist)

### Dynamic linker + core libraries

- `/lib64/ld-linux-x86-64.so.2` — real file (not a Debian multiarch symlink)
- `/lib/x86_64-linux-gnu/`:
  - `libc.so.6`, `libm.so.6`, `libdl.so.2`, `libpthread.so.0`
  - `libcrypt.so.1`, `libgcc_s.so.1`
  - `libssl.so.3`, `libcrypto.so.3`
  - `libz.so.1`, `libzstd.so.1`
  - `libnss_dns.so.2`, `libnss_files.so.2`, `libresolv.so.2`

**Not** in the baseline (image-specific, add in your overlay): `libutil`, `libstdc++`, language-specific stdlib deps.

### Identity

`/etc/passwd` and `/etc/group` contain **exactly these** reserved entries after baseline COPY:

| uid | gid | name | home | shell |
|---|---|---|---|---|
| 0 | 0 | root | / | /sbin/nologin |
| 65532 | 65532 | nonroot | /nonroot | /sbin/nologin |
| 65534 | 65534 | nobody | / | /sbin/nologin |

Derivatives that need a service user **append** to these files in their builder stage — see `memory/scratch-closures.md § "Append, never overwrite"`.

### Reserved UIDs (don't collide)

| uid | purpose |
|---|---|
| 0 | root (baseline) |
| 33 | www-data (nginx) |
| 999 | postgres (matches Docker Hub) |
| 65532 | nonroot (distroless convention) |
| 65534 | nobody (baseline) |

New Forge scratch images picking a service user should **avoid this list** to prevent collisions when images are layered or volumes are shared.

### TLS trust

- `/etc/ssl/certs/ca-certificates.crt` — Debian trixie CA bundle, refreshed on every daily rebuild.

**Important** — see `memory/scratch-closures.md § "ENV doesn't propagate"`: the baseline's `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` **does not flow to derivatives** through `COPY --from=scratch_base`. Each derivative **must re-declare** the env var in its own `ENV` directive or TLS will silently break with `CERTIFICATE_VERIFY_FAILED`.

### Network name resolution

- `/etc/nsswitch.conf` — minimal `files dns` policy
- `/etc/services` — IANA well-known ports (full Debian file)
- `/etc/protocols` — IP protocol numbers (full Debian file)
- `/etc/hosts` — `127.0.0.1 localhost` + `::1 localhost ip6-localhost ip6-loopback`

### Time

- `/usr/share/zoneinfo/*` — full IANA tzdata tree
- `/etc/localtime` — symlink to `/usr/share/zoneinfo/Etc/UTC`

### Writable directories

- `/tmp` — mode **1777** (world-writable, sticky bit)
- `/var/tmp` — mode **1777**
- `/nonroot` — owner **65532:65532**, mode **0755** (home for the nonroot user)

## Composition contract

Every Forge scratch derivative's runtime stage follows this exact shape:

```dockerfile
# syntax=docker/dockerfile:1.7
ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
FROM ${SCRATCH_BASE_REF} AS scratch_base

FROM <debian-builder-base> AS builder
# ...assemble image-specific overlay into /out...

FROM scratch AS runtime
# hadolint ignore=DL3067
COPY --from=scratch_base / /   # baseline FIRST
COPY --from=builder /out /     # image overlay SECOND — later COPY wins per-path

# MANDATORY — baseline's ENV doesn't propagate through COPY:
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
```

- The runtime stage is **literally `FROM scratch`** — the "Forge scratch image" claim is preserved.
- Baseline COPY is always first; overlays always second.
- Overlays append to `/etc/passwd` + `/etc/group`, they do not overwrite (see `memory/scratch-closures.md § "Append, never overwrite"`).
- Writable paths must exist at build time (`install -d` + `chmod` + `chown` in the builder). No runtime `mkdir` — there's no shell.

## Non-guarantees

The baseline deliberately **does not** ship:

- Any shell (`/bin/sh`, `/bin/bash`, …) — workflows using `system()` won't work in scratch runtimes
- Any package manager (`apt`, `pip`, …)
- `/dev`, `/proc`, `/sys` — kernel / docker runtime provides at container start
- `/etc/resolv.conf` — docker injects per-container at runtime
- `/etc/machine-id` — must be unique per container; shipping one in the image is a security bug
- Compilers, headers, docs, `.pyc` caches
- Package metadata (`/var/lib/dpkg/*`) — ensures `grype` finds zero Debian-source matches

## Versioning

- **Patch** (`0.2.1` style — unused today) — same file surface, refreshed content via daily rebuild.
- **Minor** (`0.2 → 0.3`) — adds new guarantees to the file-layout API or writable dirs. Backward-compatible: existing derivatives keep working, new ones can rely on the added paths.
- **Major** (`0.x → 1.0`) — would be a breaking change to the composition contract or removal of guaranteed files. Not planned.

`:latest` always points at the current highest version.

## Audit

Every published digest ships with:
- Keyless cosign signature (identity: `.github/workflows/build.yml@refs/heads/main`, issuer: `token.actions.githubusercontent.com`)
- CycloneDX SBOM attestation
- Grype scan attestation (should report zero Debian-source matches; if any appear, raise an issue)

Reproduce the scan yourself:
```bash
cosign verify \
  --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/bboortz/scratch-base-trixie:latest
```

Pin by digest in production.
