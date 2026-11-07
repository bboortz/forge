---
id: FG-026
slug: postgres-18
status: shipped
owner: bboortz
created: 2026-11-07
---

# FG-026 — PostgreSQL 18 (bump scratch + add slim variant for consumer deployments)

Homelab's nextcloud deployment currently uses `postgres:18-alpine` as a build base, layering apt packages (`htop curl netcat gzip procps`) + a custom `postgresql.conf` + `pg_hba.conf` + `init-nextcloud.sql` + `postgres-maintenance.sh`. The maintainer wants to swap in a Forge-published postgres-18 image for the same supply-chain hygiene we give python + nginx.

`postgres-scratch-trixie:17` already exists, but nextcloud cannot adopt it as-is:
- Upstream `docker-entrypoint.sh` is a bash script that handles `POSTGRES_*_FILE` secrets + `/docker-entrypoint-initdb.d/*.sql` execution. **No shell in scratch → these features die.**
- The nextcloud `postgres-maintenance.sh` is a bash script that calls `psql`. **Needs a shell.**

Two tracks in this FG:

1. **Add `postgres-slim-trixie` (new consumer-facing shelled variant)** — `FROM postgres:18` (Debian-trixie-based) + `apt-get upgrade` + Forge's scan/sign/attest treatment. Preserves the upstream entrypoint so secrets-from-FILE, init.d SQL, custom config, and shell scripts all work. This is what nextcloud actually pulls.
2. **Bump `postgres-scratch-trixie:17` → `:18`** — keeps the minimalist option for consumers who pre-initialize via sidecar + run scripts in a separate container. Version refresh only.

Rationale: parallels python's shape (`python-slim-trixie` consumer-facing + `python-scratch-trixie` minimal). The slim variant is where downstream apps live; the scratch variant is the differentiator.

## 9 canonical answers

1. **Who** — Benjamin (homelab maintainer) wants `ghcr.io/bboortz/postgres-slim-trixie:18` for the nextcloud pg instance. Secondary consumer: anyone who uses postgres as a build base and relied on `postgres:18-alpine` or `postgres:18` directly.

2. **When** — Fires the next time the maintainer reaches for `postgres:18-alpine` or `postgres:17-scratch` and wants Forge's scan/sign/attest attached. The scratch variant bump fires when consumers who already adopted `-scratch:17` want `18`.

3. **What success looks like**:
   - `ghcr.io/bboortz/postgres-slim-trixie:18` publishes daily with cosign signature + SBOM + scan attestations.
   - Nextcloud's `postgres/Dockerfile` switches `FROM postgres:18-alpine` to `FROM ghcr.io/bboortz/postgres-slim-trixie:18` with no change to its config mounts, maintenance script, or docker-compose.
   - `ghcr.io/bboortz/postgres-scratch-trixie:18` publishes alongside `:17` (or bumps `:latest` to 18). Existing scratch consumers migrate by changing their pin.

4. **Urgency** — Quality-of-life. Not security-critical (homelab is already on `postgres:18-alpine` with its own upgrade cadence). Adoption value: homelab gets the same signed/scanned guarantees as python-slim + nginx-scratch.

5. **Happy path**:
   1. Forge publishes `postgres-slim-trixie:18` + bumps `postgres-scratch-trixie` to `:18`.
   2. Homelab rebases `nextcloud/postgres/Dockerfile` onto `postgres-slim-trixie:18`.
   3. Drops the apk-based `htop curl netcat gzip procps` install (Debian equivalents either already present or added via `apt-get install`).
   4. Runs `cosign verify ghcr.io/bboortz/postgres-slim-trixie:18` to confirm supply chain.
   5. Nothing else in `docker-compose.yml.j2` changes.

6. **Edge cases / failure modes**:
   - **Alpine → Debian locale differences** — nextcloud init.sql uses standard SQL (no OS-specific paths); low risk.
   - **ICU version drift** — postgres 18 was built against a specific `libicu` on Debian trixie. Reindexing-dependent databases need an `REINDEX DATABASE` after migration. Document in homelab adoption notes.
   - **`htop netcat procps` absence** — nextcloud's Dockerfile explicitly layers these for ops convenience. Debian has `htop procps netcat-openbsd` — document the equivalent `apt-get install` line.
   - **PG 17 → 18 major version upgrade** (homelab currently runs 18 already, so this doesn't apply; it would for anyone on scratch:17 who bumps).

7. **Out of scope**:
   - Postgres 18 major-version migration tooling (homelab already runs `postgres-migrate.sh` — no new help needed from Forge).
   - Multi-arch (amd64-only, same as every other image).
   - Postgres-specific sid pins (none required at story draft time).
   - Rewriting nextcloud's docker-compose to use the scratch variant with sidecar init (would require operator effort for marginal benefit).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.postgres-slim-nextcloud-compatible` — postgres-slim-trixie preserves upstream entrypoint behavior: secrets-from-FILE, init.d SQL, custom config override, shell-script maintenance hooks.
   - EXT `image.postgres-scratch-nonroot` — version bump from 17 → 18 (keeps scratch promise contract otherwise unchanged).
   - EXT `publish.ghcr-public-pull` — new publicly-pullable image at `ghcr.io/bboortz/postgres-slim-trixie:18`.

## Gherkin acceptance

```
Scenario: postgres-slim-trixie:18 publishes with the standard Forge triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists postgresql-18
   And the grype attestation is attached

Scenario: postgres-slim-trixie:18 runs the upstream docker-entrypoint
  Given a container run with POSTGRES_DB_FILE + POSTGRES_USER_FILE + POSTGRES_PASSWORD_FILE
  When the container starts for the first time
  Then it initdb's the cluster using the secret values
   And /docker-entrypoint-initdb.d/*.sql files execute

Scenario: postgres-slim-trixie:18 honors custom config mounts
  Given /etc/postgresql/postgresql.conf + /etc/postgresql/pg_hba.conf mounted
  When started with `postgres -c config_file=... -c hba_file=...`
  Then postgres uses the mounted files
   And pg_isready -h 127.0.0.1 returns 0

Scenario: postgres-scratch-trixie:18 keeps its existing scratch contract
  Given the FG-007 sidecar-init smoke test suite
  When run against postgres-scratch-trixie:18
  Then all FG-007 scenarios still pass (no behavior change beyond version bump)
   And the image still has no shell, no apt, no dpkg database

Scenario: homelab nextcloud adopts postgres-slim-trixie:18 with minimal diff
  Given homelab/docker/nextcloud/postgres/Dockerfile
  When FROM is changed to ghcr.io/bboortz/postgres-slim-trixie:18
   And the apk-based install is replaced with apt-get install (htop curl netcat-openbsd procps gzip)
  Then `docker compose up db` starts correctly
   And the healthcheck turns green
   And pg_stat_statements + pg_trgm extensions load via init-nextcloud.sql
```

## References

- Plan: `docs/plan/FG-026-postgres-18-plan.md`
- Red test: `tests/acceptance/test_FG_026_postgres-18.sh`
- Capabilities: see `docs/CAPABILITIES.md`
- Homelab touchpoint: `~/git/homelab/docker/nextcloud/postgres/Dockerfile`
