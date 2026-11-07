# FG-026 — Plan: PostgreSQL 18 (scratch bump + new slim variant)

**Story**: [`docs/stories/FG-026-postgres-18.md`](../stories/FG-026-postgres-18.md)
**Status**: in-progress
**Branch**: `feat/FG-026-postgres-18`

## Design delta

Two tracks in one PR.

### Track A — bump `postgres-scratch-trixie` from postgres-17 to postgres-18
- `images/postgres-scratch-trixie/image.yaml`: `tag: "17"` → `tag: "18"`
- `images/postgres-scratch-trixie/Dockerfile`: `postgresql-17` + `postgresql-client-17` → `postgresql-18` + `postgresql-client-18`; all `/usr/lib/postgresql/17` + `/usr/share/postgresql/17` paths → `/18`
- `images/postgres-scratch-trixie/PROMISES.yaml`: `version: "0.1"` → `"0.2"` (FG-010 semver gate); all textual references to "postgres 17" / "PostgreSQL 17" → "18"
- `images/postgres-scratch-trixie/tests/smoke_server_accepts.sh`: sidecar-init `postgres:17` → `postgres:18`; `IMAGE_TAG` default `17` → `18`
- Regenerate `images/postgres-scratch-trixie/scan-baseline.json` against the postgres-18 build

### Track B — add `postgres-slim-trixie` (new)
- `images/postgres-slim-trixie/image.yaml`: `tag: "18"`, no `depends_on` (base tier — like python-slim-trixie)
- `images/postgres-slim-trixie/Dockerfile`: `FROM postgres:18` + apt-upgrade; one-stage, preserves upstream entrypoint. No forge-builder-trixie base — would strip the `postgres:18` entrypoint + binaries.
- `images/postgres-slim-trixie/PROMISES.yaml`: declares `runtime.postgres-binary`, `runtime.docker-entrypoint`, `runtime.initdb-support`, `runtime.psql-client`, `files.ca-certificates`, `shape.size-budget`
- Smoke tests: `smoke_postgres_version.sh`, `smoke_entrypoint_shell.sh`, `smoke_psql.sh`, `smoke_ca_bundle.sh`, `smoke_size.sh`
- `images/postgres-slim-trixie/scan-baseline.json`: generated at first build

## Alternatives rejected

- **Only bump scratch to 18, no slim variant** — the user's actual goal (homelab nextcloud adoption) requires the upstream entrypoint. Scratch has no shell → `docker-entrypoint.sh` can't run → nextcloud can't adopt. Half the FG wouldn't deliver the stated user value.
- **FROM forge-builder-trixie for postgres-slim** — forge-builder-trixie is `python:3.13-slim-trixie + apt-upgrade + syft`. Postgres-slim-trixie needs the upstream `postgres:18` entrypoint + binaries + initdb.d/ directory. FROM-ing forge-builder would strip all of that.
- **Alpine-based postgres-slim** — Debian-trixie is the standard Forge base. Keeping Debian means operators already comfortable with Debian stay comfortable; sid pinning (differentiator) works.
- **Skip the scratch bump** — leaves existing scratch consumers stuck on an aging major. Cheap to bump at the same time.

## Breaking changes

**`postgres-scratch-trixie:17` tag becomes stale.** Daily cron now publishes `:18` as `:latest`. Consumers pinned to `:17` need to re-pin explicitly to continue receiving updates. Documented in INDEX.

PROMISES semver bump 0.1 → 0.2 is routine (version-detail change, no removed promises; FG-010 verifier accepts).

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass
- FG-026 acceptance test green
- FG-007 (existing postgres-scratch-trixie smoke suite) still green on the bumped image
- scan-baseline.json regenerated for both images
- `make test-fast` green

## Rollout plan

Lands on `dev` via PR. Merges to `main` via `release.yml` dispatch. Next 03:00 UTC `build.yml` cron publishes:
- `ghcr.io/bboortz/postgres-scratch-trixie:18` + `:latest`
- `ghcr.io/bboortz/postgres-slim-trixie:18` + `:latest`

Homelab adoption diff documented in the story — ~5-line change to `~/git/homelab/docker/nextcloud/postgres/Dockerfile`.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: postgres-slim-trixie:18 publishes with the standard Forge triple | `tests/acceptance/test_FG_026_postgres-18.sh` § 1 | ⏳ |
| Scenario: postgres-slim-trixie:18 runs the upstream docker-entrypoint | § 2 + smoke_entrypoint_shell.sh | ⏳ |
| Scenario: postgres-slim-trixie:18 honors custom config mounts | § 3 | ⏳ |
| Scenario: postgres-scratch-trixie:18 keeps its existing scratch contract | FG-007 full suite still green | ⏳ |
| Scenario: homelab nextcloud adopts postgres-slim-trixie:18 with minimal diff | doc — adoption diff in story | ⏳ |
| CAP `image.postgres-slim-nextcloud-compatible` | `docs/CAPABILITIES.md` + test | ⏳ |
| EXT `image.postgres-serves-sql` | postgres-17 → 18 version bump | ⏳ |
