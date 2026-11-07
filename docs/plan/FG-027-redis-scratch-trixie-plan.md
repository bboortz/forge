# FG-027 — Plan: redis-scratch-trixie

**Story**: [`docs/stories/FG-027-redis-scratch-trixie.md`](../stories/FG-027-redis-scratch-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-027-redis-scratch-trixie`

## Design delta

### `images/redis-scratch-trixie/` (new)

- `image.yaml`: tag `"8"`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage. Builder `FROM forge-builder-trixie` (FG-025). `apt-get install redis-server redis-tools` → scratch overlay via `install -d ... + cp` (no `apt-get upgrade` — forge-builder-trixie pre-applied it). FG-020 SBOM via syft.
- Runtime `FROM scratch`: overlay the baseline (scratch-base-trixie) then redis-specific overlay (redis-server, redis-cli, aof/rdb check binaries, libatomic + libcap + libjemalloc + liblzf + libstdc++ + libsystemd, redis user @ uid 999, writable /data).
- `ENTRYPOINT ["/usr/bin/redis-server"]`, `CMD []`, `USER redis`, `WORKDIR /data`, `EXPOSE 6379`.
- `PROMISES.yaml`: declares `runtime.redis-server-binary`, `runtime.redis-cli-binary`, `runtime.server-accepts-clients`, `runtime.user-redis`, `image.no-shell`, `files.sbom-embed`, `files.tls-stack`, `shape.size-budget` (hard 50 MB ceiling).
- `EXPECTATIONS.yaml`: FG-010 contract on scratch-base-trixie ≥ 0.2 covering dynamic-linker + core-glibc + tls-stack + compression + network-data + time + writable-dirs.tmp + absence.shell.

### Smoke tests

Six, co-located under `images/redis-scratch-trixie/tests/`:

- `smoke_binary_runs.sh` — `redis-server --version` + `redis-cli --version` are v8.x.
- `smoke_server_accepts.sh` — boot server + sidecar `redis-cli PING` + SET/GET round-trip + clean SIGTERM. Uses `--network=container:...` because redis-8 protected-mode blocks port-forwarded pings.
- `smoke_user_redis.sh` — `/etc/passwd` has `redis:x:999:999:` entry.
- `smoke_no_shell.sh` — `/bin/sh`, `/bin/bash`, `/bin/dash`, `/usr/bin/sh` all absent.
- `smoke_contents.sh` — required files present via `docker cp` (redis binaries, /sbom.json, CA bundle, /etc/passwd); /sbom.json is well-formed CycloneDX.
- `smoke_size.sh` — image ≤ 50 MB absolute ceiling (shared size smoke; ~30 MB in practice).

### No workflow changes

`.github/workflows/build.yml`'s discover job finds the image dir automatically. No matrix edits needed.

## Alternatives rejected

- **Use `redis:8-alpine` as the builder** — Alpine's package format is incompatible with our dpkg-based SBOM pipeline (FG-020). Debian native avoids special-casing.
- **Add a `redis-slim-trixie` variant alongside** — no consumer needs it yet. Homelab's usage pattern is scratch-friendly. Easy to add later if demand surfaces.
- **Build redis from source via PGDG-style upstream apt repo** — Debian trixie already ships redis 8.0.2 natively. No need for a third-party repo. (Contrast: postgres 18 isn't in trixie, so FG-026 needed PGDG.)
- **Default `--protected-mode no`** — insecure. Protected-mode is the right default; smoke tests + homelab deployments use the sidecar / same-netns pattern to work with it.

## Breaking changes

None user-facing. New image, no existing consumers.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass
- FG-027 acceptance test green
- `make test-fast` green
- All 6 smoke tests pass against the built image
- scan-baseline.json generated

## Rollout plan

Lands on `dev` via PR. Promotes to `main` via `release.yml` dispatch. Next 03:00 UTC `build.yml` cron publishes `ghcr.io/bboortz/redis-scratch-trixie:8` + `:latest`.

Homelab adoption diff is a single-line swap of the FROM + removal of the apk upgrade step.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: redis-scratch-trixie:8 publishes with the standard triple | `tests/acceptance/test_FG_027_redis-scratch-trixie.sh` § 1 | ⏳ |
| Scenario: redis-server boots and serves clients end-to-end | § 2 + smoke_server_accepts.sh | ⏳ |
| Scenario: image has no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: redis user is uid 999 | § 4 + smoke_user_redis.sh | ⏳ |
| Scenario: SBOM is embedded at /sbom.json | § 5 + smoke_contents.sh | ⏳ |
| CAP `image.redis-serves-cache` | `docs/CAPABILITIES.md` + smoke_server_accepts.sh | ⏳ |
| EXT `image.no-shell` + `image.zero-os-cves` + `scan.sbom-embed` + `build.two-stage-scratch` | smokes + scan-baseline | ⏳ |
