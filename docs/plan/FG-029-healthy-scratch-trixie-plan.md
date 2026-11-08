# FG-029 — Plan: healthy-scratch-trixie

**Story**: [`docs/stories/FG-029-healthy-scratch-trixie.md`](../stories/FG-029-healthy-scratch-trixie.md)
**Status**: in-progress
**Branch**: `feat/FG-029-healthy-scratch-trixie`

## Design delta

### `images/healthy-scratch-trixie/` (new)

- `image.yaml`: tag `"1"`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage. Builder `FROM forge-builder-trixie` installs `wget netcat-openbsd coreutils`; syft generates `/sbom.json`; runtime `FROM scratch` overlays the baseline + utilities overlay.
- Runtime overlay carries:
  - `/usr/bin/wget` (Debian native, GnuTLS-linked)
  - `/usr/bin/nc` (resolved from `/bin/nc.openbsd` — alternatives system collapsed into a direct binary path)
  - `/usr/bin/sleep` (GNU coreutils)
  - 11 wget-specific libs: libpcre2-8, libuuid, libidn2, libnettle, libgnutls, libpsl, libunistring, libp11-kit, libtasn1, libhogweed, libgmp, libffi
  - 2 nc-specific libs: libbsd, libmd
- `CMD ["/usr/bin/sleep", "infinity"]` — container stays up without a shell wrapper.
- `USER 65532:65532` (baseline's `nonroot`). No privileged capabilities needed.

### Smoke tests (6)

- `smoke_binary_runs.sh` — wget / nc / sleep all runnable.
- `smoke_cmd_sleeps.sh` — default CMD = `["/usr/bin/sleep", "infinity"]`, container stays running, clean SIGTERM.
- `smoke_sidecar_healthcheck.sh` — end-to-end: boot redis-scratch-trixie target, run healthy-scratch-trixie in shared netns, confirm `nc -z` succeeds against live port + fails against closed port, `wget` reaches target via shared loopback.
- `smoke_no_shell.sh` — /bin/{sh,bash,dash}, /usr/bin/sh absent.
- `smoke_contents.sh` — binaries + /sbom.json + CA bundle + /etc/passwd present; SBOM is valid CycloneDX containing wget + netcat-openbsd + coreutils components.
- `smoke_size.sh` — hard 30 MB absolute ceiling (24 MB actual; GnuTLS closure is the dominant cost).

### Acceptance test

`tests/acceptance/test_FG_029_healthy-scratch-trixie.sh` with 4 sections: file layout, build, smoke suite, image.yaml.

### No workflow changes

`.github/workflows/build.yml`'s discover job auto-detects the image.

## Alternatives rejected

- **Include curl** — closure drags in ~15 MB (GSSAPI, LDAP, brotli, GnuTLS alternate). No homelab consumer needs it; defeats "minimal sidecar."
- **Use `wget2`** (lighter binary) — not in Debian trixie at a stable version compatible with homelab's wget flag usage (`-qO- -T 5`).
- **Build wget against OpenSSL** — would require from-source build; our Debian-native pipeline doesn't do that today. Keeping GnuTLS is the lowest-friction choice.
- **Add `ping` / ICMP tools** — requires CAP_NET_RAW; sidecar runs as non-root. HTTP + TCP healthchecks cover 100% of homelab's use cases.
- **Replace both `nc` + `wget`** with a Go/Rust single binary (e.g., `healthcheck`) — new maintenance surface; wget has 20+ years of operator muscle memory.

## Breaking changes

None. New image, no existing consumers.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass
- FG-029 acceptance test green (4 sections)
- All 6 smoke tests pass
- `make test-fast` green

## Rollout plan

Lands on `dev` via PR. Promotes to `main` via `release.yml` dispatch. Next 03:00 UTC `build.yml` cron publishes `ghcr.io/bboortz/healthy-scratch-trixie:1` + `:latest`.

Homelab adoption diff (per stack): change `image:` and drop the `command:` line (CMD is baked). 2-line change × 4 stacks.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: healthy-scratch-trixie:1 publishes with the standard triple | `tests/acceptance/test_FG_029_healthy-scratch-trixie.sh` § 1 + § 2 | ⏳ |
| Scenario: default CMD sleeps forever | § 3 + smoke_cmd_sleeps.sh | ⏳ |
| Scenario: wget via shared netns | § 3 + smoke_sidecar_healthcheck.sh | ⏳ |
| Scenario: nc -z TCP port scan | § 3 + smoke_sidecar_healthcheck.sh | ⏳ |
| Scenario: no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: image is small | § 3 + smoke_size.sh (30 MB ceiling) | ⏳ |
| Scenario: SBOM embedded | § 3 + smoke_contents.sh | ⏳ |
| CAP `image.healthy-sidecar` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
| EXT `image.no-shell` + `scan.sbom-embed` + `build.two-stage-scratch` | smokes + scan-baseline | ⏳ |
