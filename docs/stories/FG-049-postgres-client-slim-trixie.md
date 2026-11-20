---
id: FG-049
slug: postgres-client-slim-trixie
status: ready
owner: bboortz
created: 2026-11-10
---

# FG-049 — postgres-client-slim-trixie (optional smaller forge-rooted client toolkit)

`postgres-scratch-trixie` deliberately ships no shell. That's a differentiator-grade promise (`absence.shell`) but it breaks every PostgreSQL client that uses `popen()` or `system()` internally — notably `pg_dumpall` and `initdb`. Both binaries are present in the scratch image and both report cryptic "program X not found in the same directory as Y" errors because the actual ENOENT is on `/bin/sh`, not on the sibling binary they're trying to spawn.

**A working solution already ships.** `postgres-slim-trixie:18` (FG-026, 438 MB, `FROM postgres:18` + apt-upgrade + CA bundle) covers the pg_dumpall / initdb / pg_amcheck workflows today — it has `/bin/sh`, `apt`, and all client binaries behave normally. The 2026-11-10 operator-facing fix is the one-line doc update on postgres-scratch-trixie's `absence.shell` PROMISE that points operators at FG-026 (shipped alongside this story as a parallel doc-only commit).

This story proposes an **optional smaller forge-rooted sibling**: `postgres-client-slim-trixie:18`, `FROM ghcr.io/bboortz/debian-slim-trixie:latest` + `postgresql-client-18` from PGDG + a shell. Server binaries (`postgres`, `initdb`, `pg_ctl`) are deliberately NOT shipped. The pitch:

- ~200 MB smaller than postgres-slim-trixie (projected 150-200 MB vs 438 MB)
- Role-separated from the server image — operator intent ("I want to run a backup job") is explicit in the pull reference
- Forge-rooted (consumes debian-slim-trixie, not `postgres:18` upstream) → better fits FG-042's single-upstream-consumption rule

Trade-off: it's +1 image to build, sign, scan, and maintain forever, for a workflow that postgres-slim-trixie already handles. Ship this only when the maintenance tax is worth the role clarity + size reduction.

Division of labor if this ships:

- **postgres-scratch-trixie:18** — serve SQL (no shell, minimal CVE surface)
- **postgres-slim-trixie:18** (FG-026) — full upstream-compatible postgres entrypoint + shell + client binaries. Operators who want "just works like Docker Hub postgres:18" reach for this.
- **postgres-client-slim-trixie:18** (this story) — back up / restore / connect from scripts (shell present, client tooling only, smaller base)

## 9 canonical answers

1. **Who** — ops / backup operator running scheduled `pg_dumpall` against a `postgres-scratch-trixie` cluster. Secondary: homelab operator wiring a cron sidecar next to a postgres service. Tertiary: auditor validating "backup of forge-signed postgres cluster uses a forge-signed client."

2. **When** — fires every time an operator needs `pg_dumpall`, `pg_basebackup`, `pg_receivewal`, or `pg_amcheck` against a forge postgres cluster, or wants to run ad-hoc `psql` from a signed base image rather than installing `postgresql-client` on the host. Daily cron publishes the image.

3. **What success looks like**:
   - `ghcr.io/bboortz/postgres-client-slim-trixie:18` publishes with cosign + SBOM + scan attestations.
   - `docker run --rm --network=host ghcr.io/bboortz/postgres-client-slim-trixie:18 pg_dumpall -h 127.0.0.1 -U postgres` streams a SQL dump against a running `postgres-scratch-trixie` cluster. Zero "No such file or directory" errors.
   - Every client binary (`pg_dump`, `pg_dumpall`, `pg_restore`, `psql`, `pg_basebackup`, `pg_receivewal`, `pg_amcheck`, `pg_isready`) is present and prints `--version` without error.
   - Server binaries are explicitly absent — `/usr/lib/postgresql/18/bin/postgres` and `/usr/lib/postgresql/18/bin/initdb` must NOT be in the image (size discipline + role clarity).
   - Image size ≤ 200 MB (postgres-scratch is ~110 MB; adding shell + apt + full client set adds ~70-90 MB).
   - Runs as `postgres` uid 999 for predictable file ownership on backup volumes shared with the server.

4. **Urgency** — quality-of-life only. The immediate problem (operator surprised by pg_dumpall ENOENT on 2026-11-10) is already solved by the doc-only fix pointing at `postgres-slim-trixie:18` (shipped, works today). This story is the "smaller forge-rooted client-only variant" follow-up — ship when multiple operators hit the 438 MB sidecar weight as inconvenient, OR when a new postgres-based image lands that would benefit from a leaner shared base.

5. **Happy path**:
   1. Operator runs daily backup sidecar via homelab compose: `postgres-backup` service `FROM ghcr.io/bboortz/postgres-client-slim-trixie:18`, mounts backup volume on `/backups`, runs `pg_dumpall --host=postgres --username=postgres --file=/backups/dump.sql`.
   2. Dump completes; file lands on the volume with uid 999 ownership.
   3. Separately, operator can also run ad-hoc `psql` from the same image for interactive queries: `docker run --rm -it --network=host ghcr.io/bboortz/postgres-client-slim-trixie:18 psql -h 127.0.0.1 -U postgres`.

6. **Edge cases / failure modes**:
   - **Operator tries to run `postgres` or `initdb` from this image** — they're not shipped. Error is immediate (`exec: postgres: not found`) and documented in PROMISES. Reverse direction: a scratch cluster's data dir was `initdb`'d by the official postgres:18 sidecar; postgres-client-slim-trixie reads that data fine via psql because uid 999 matches.
   - **Backup volume shared with cluster data volume via different uid** — mitigated by pinning postgres uid 999 (Docker Hub convention, same as postgres-scratch-trixie).
   - **TLS to remote cluster via `postgres_fdw` chaining** — libpq handles its own TLS via OpenSSL; CA bundle inherited from debian-slim-trixie.
   - **SBOM scanner reports postgres server-package CVEs** — we installed `postgresql-client-18`, not `postgresql-18`. Only client-side CVE surface.
   - **Nonroot client needs to write temp files for pg_dump** — `/tmp` has mode 1777 from debian-slim-trixie.
   - **PGDG apt key expires / PGDG repo unreachable during cron** — same risk postgres-scratch-trixie already carries (shared PGDG setup). Mitigation inherited: scan-regression gate keeps old image live until next successful publish.

7. **Out of scope**:
   - **Server binaries** (`postgres`, `initdb`, `pg_ctl`) — role confusion vs postgres-scratch-trixie; keep the image client-only.
   - **Database migration tools** (flyway, liquibase, atlas) — out of scope; different concern. Deferred to IDEAS if an operator asks.
   - **Scratch runtime** — defeats the entire purpose (shell IS the differentiator vs postgres-scratch-trixie).
   - **Multi-arch** — amd64-only matches every other Forge image. arm64 later with the rest.
   - **Cron scheduler baked in** — image is a toolkit, not a job runner; operator wires their own cron / systemd timer / k8s CronJob around it.
   - **Automatic rotation / retention** — pg_dumpall emits one file; retention is an operator concern. Deferred to IDEAS.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.postgres-client-tools` — ships the complete postgresql-client-18 toolkit (pg_dump + pg_dumpall + pg_restore + psql + pg_basebackup + pg_receivewal + pg_amcheck + pg_isready). Every binary executes standalone + via popen/system.
   - NEW `image.postgres-client-pg_dumpall-works` — pg_dumpall end-to-end against a live `postgres-scratch-trixie` cluster produces a non-empty, replay-able SQL dump. The shell-dependency class of bug documented on `absence.shell` is cleanly resolved in this sibling image.
   - NEW `image.postgres-client-no-server` — server binaries (`postgres`, `initdb`, `pg_ctl`) are explicitly NOT shipped. Image is a client toolkit, not a second server image.
   - NEW `image.postgres-client-nonroot` — runs as uid 999 (postgres user), matching postgres-scratch-trixie for shared-volume compatibility.
   - EXT `image.has-shell` — now lists postgres-client-slim-trixie.
   - EXT `image.absence.shell` (on postgres-scratch-trixie) — description updated to explicitly reference postgres-client-slim-trixie as the sibling for `pg_dumpall` / `initdb` / `pg_amcheck` workflows. (Shipped as a doc-only fix alongside this story.)

## Gherkin acceptance

```
Scenario: postgres-client-slim-trixie:18 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists postgresql-client-18 + libpq5 + openssl + their resolved versions
   And the grype scan is attached

Scenario: every client binary runs standalone
  Given the built image
  When each of pg_dump, pg_dumpall, pg_restore, psql, pg_basebackup, pg_receivewal, pg_amcheck, pg_isready is invoked with --version
  Then each prints its version line and exits 0

Scenario: pg_dumpall end-to-end against a live postgres cluster
  Given a running postgres-scratch-trixie cluster initialized by a sidecar
  When `docker run --rm --network=<net> postgres-client-slim-trixie:18 pg_dumpall -h <pg-host> -U postgres --no-password` runs
  Then stdout contains a valid pg_dumpall header line starting with "--"
   And stdout contains at least one "CREATE DATABASE" or "\connect" line
   And exit code is 0
   And no "No such file or directory" error appears on stderr

Scenario: server binaries are deliberately absent
  Given the built image
  When `test -x /usr/lib/postgresql/18/bin/postgres` runs via the image's shell
   And `test -x /usr/lib/postgresql/18/bin/initdb` runs
   And `test -x /usr/lib/postgresql/18/bin/pg_ctl` runs
  Then each test exits nonzero (binaries not present)

Scenario: Image ships a shell (slim contract)
  Given the built image
  When `docker run --rm --entrypoint=/bin/sh <image> -c 'echo ok'` runs
  Then stdout is "ok"

Scenario: Runs as postgres uid 999
  Given the built image
  When `docker inspect --format '{{.Config.User}}' <image>` is read
  Then the output is "999:999" or "postgres"
   And `docker run --rm --entrypoint=id <image>` reports uid=999 gid=999

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 200 MB

Scenario: PATH and PGDATA env sane for client use
  Given the built image
  When `docker inspect --format '{{.Config.Env}}' <image>` is read
  Then PATH contains /usr/lib/postgresql/18/bin
   And PGHOST is NOT set (operator supplies per invocation)

Scenario: postgres-scratch-trixie's absence.shell now points here
  Given postgres-scratch-trixie's PROMISES.yaml
  When its absence.shell promise description is read
  Then it explicitly references postgres-client-slim-trixie as the sibling for pg_dumpall / initdb / pg_amcheck workflows

Scenario: Co-use pattern — scratch server + slim client over a shared network
  Given postgres-scratch-trixie:18 running with a cluster initialized by the Docker Hub postgres:18 sidecar
   And postgres-client-slim-trixie:18 available
  When the operator runs `psql -h <scratch-host> -U postgres -c 'SELECT 1'` from the slim client image
  Then the output is a valid psql result set with the integer 1
   And the operator can also run `pg_dumpall -h <scratch-host> -U postgres > /backups/dump.sql` from the slim client against the same server with no errors
```

## References

- Plan: `docs/plan/FG-049-postgres-client-slim-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_049_postgres-client-slim-trixie.sh`
- Related: FG-007 (postgres-scratch-trixie — the scratch server this is the client-side sibling of)
- Related: **FG-026 postgres-slim-trixie** — already-shipped Docker-Hub-rooted slim variant. Covers the same pg_dumpall workflow at 438 MB. FG-049 is the lean forge-rooted alternative; ship only when the maintenance tax is worth the size + role-clarity gains.
- Related: FG-042 (debian-slim-trixie — this story's runtime base, dogfooded)
- Related: `memory/scratch-closures.md` § "Scratch has no shell — anything using `system()` won't work in-container"
- Trigger: 2026-11-10 operator report of pg_dumpall ENOENT on postgres-scratch-trixie. Immediate fix: doc update pointing at postgres-slim-trixie:18. This story addresses the optional smaller-sibling follow-up.
