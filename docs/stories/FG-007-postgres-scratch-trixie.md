---
id: FG-007
slug: postgres-scratch-trixie
status: shipped
owner: bboortz
created: 2026-11-04
---

# FG-007 — postgres-scratch-trixie: signed, minimal, no-shell postgres 17

Publish `ghcr.io/bboortz/postgres-scratch-trixie:17` (+ `-amd64`, `:latest`, `:latest-amd64`) — Debian trixie's PostgreSQL 17.11 on a `FROM scratch` runtime. No shell, no `apt`, no `dpkg` database, **no LLVM JIT**. Serves SQL queries end-to-end; `grype` against the base layer finds zero Debian-source matches.

Third image in the catalogue. First image whose minimum viable workflow needs a sidecar: PostgreSQL's `initdb` uses `system()` internally, which requires `/bin/sh` — not available in our scratch runtime. The server itself has no such dependency, so the image works as a server runtime; one-time cluster initialization uses an external init sidecar (Docker Hub's `postgres:17` or any shelled postgres image; forge may ship its own `postgres-slim-trixie` later).

## 9 canonical answers

1. **Who** — ops team running stateful PostgreSQL workloads who wants a signed, minimal server image + the "actually zero Debian-source CVEs" proof.
2. **When** — PR / pre-push / daily cron matrix.
3. **What success looks like** —
   - `docker run --rm forge-local/postgres-scratch-trixie:17 postgres --version` prints `PostgreSQL 17.11`
   - A postgres:17-initialized data volume mounted into the scratch image starts, accepts `psql -c 'SELECT 1'`, returns `1`
   - `cosign verify ... postgres-scratch-trixie:17` exits 0 after first publish
   - `docker run --rm --entrypoint=/bin/sh ...` fails (no shell)
   - `grype` matches with `artifact.type == "deb"` = 0
   - Image size ≤ **150 MB**
4. **Urgency** — product tier; completes the "three canonical base images" (python, nginx, postgres) story and gives FG-005 three concrete scratch closures to extract a baseline from.
5. **Happy path** —
   1. Scaffold `images/postgres-scratch-trixie/` with two-stage Dockerfile; builder on python:3.13-slim-trixie installs postgresql-17 + postgresql-client-17; runtime FROM scratch with explicit COPYs of binaries + libs + shared data.
   2. Ship 7 binaries: postgres, initdb, pg_ctl, pg_isready, psql, pg_dump, pg_restore, pg_config, pg_dumpall. Drop every Debian wrapper (pg_ctlcluster etc. — they need Perl + multi-cluster config).
   3. ldd closure is big (libicu + libxml + libpam + libldap + libkrb5 + libssl + libreadline — ~50 libs in total).
   4. Copy `/usr/share/postgresql/17/` wholesale — timezone sets, encoding/locale conversions, extension SQL. ~30 MB. Required by initdb and runtime.
   5. Pin postgres uid/gid to **999:999** matching Docker Hub's official postgres image convention. Trixie's dynamic uid assignment would mismatch other ecosystem images that initdb volumes.
   6. Set `USER postgres` + `PGDATA=/var/lib/postgresql/data` + `PATH=/usr/lib/postgresql/17/bin` so `docker run <image> postgres`/`initdb`/`psql` all resolve clean.
   7. Smoke tests: binary-runs, server-accepts (sidecar initdb → scratch postgres → scratch psql SELECT 1), no-shell, zero-OS-CVEs, size.
6. **Edge cases / failure modes** —
   - **initdb doesn't run in scratch**: `system()` → `/bin/sh` → ENOENT. Documented limitation; sidecar required for one-time init.
   - **UID mismatch** between our scratch postgres and an initdb'd volume → EACCES. Resolved by pinning uid 999 to match Docker Hub.
   - **pg_hba.conf scope**: default rules only allow 127.0.0.1/32; container-to-container traffic hits via docker bridge gateway (172.17.0.1), which fails. Smoke test appends `host all all 0.0.0.0/0 trust` — acceptable for a trust-only test cluster. Consumers run with real auth.
   - **LLVM JIT excluded**: postgresql-17-jit would add ~100 MB of libLLVM. Dropped. Consumers who need JIT either build on this image + add libLLVM manually, or use the future postgres-slim-trixie variant.
   - **`postmaster` binary no longer exists** in postgres 17 — it was a symlink in older versions; now `postgres` is the single server entry point. COPY list adjusted.
7. **Out of scope** — multi-arch arm64 (future); sid pins; postgres extensions beyond what ships in postgresql-17 defaults; replication tests; pg_upgrade; the scratch-base-trixie baseline (FG-005 lands next and refactors python-scratch + nginx-scratch + postgres-scratch onto it).
8. **How we know it's done** — see Gherkin below.
9. **Capabilities** —
   - NEW `image.postgres-serves-sql` — scratch postgres starts, accepts `SELECT 1` end-to-end against an externally-initialized cluster
   - NEW `test.sidecar-init` — the "use a shelled sidecar to initialize state, then run scratch" test pattern (first use; will apply to anything else with shell-requiring init)
   - EXT `image.no-shell`, `image.zero-os-cves`, `test.size-budget`, `test.smoke-server-helper` (reused for the pg_isready readiness probe analogue)

## Gherkin acceptance

```
Scenario: postgres binary reports its version
  When docker run --rm <image> postgres --version
  Then exit 0 and stdout matches /PostgreSQL\) 17\./

Scenario: scratch postgres serves SELECT 1 end-to-end
  Given a data volume initialized by a sidecar (postgres:17)
  When scratch postgres starts against that volume and psql queries it
  Then psql -At -c 'SELECT 1' returns "1"

Scenario: no shell in postgres-scratch-trixie
  When docker run --rm --entrypoint=/bin/sh fails
  Then smoke_no_shell.sh exits 0

Scenario: grype finds zero Debian matches
  When grype runs
  Then matches[] | select(.artifact.type == "deb" or == "dpkg") | length == 0

Scenario: image size ≤ 150 MB
  When docker image inspect size is read
  Then size ≤ 150_000_000 bytes

Scenario: UID of postgres user is 999 (Docker Hub convention)
  Given the image
  When /etc/passwd is extracted
  Then the postgres line reads `postgres:x:999:999:...`
```

## References

- Plan: [`docs/plan/FG-007-postgres-scratch-trixie-plan.md`](../plan/FG-007-postgres-scratch-trixie-plan.md)
- Red test: [`tests/acceptance/test_FG_007_postgres-scratch-trixie.sh`](../../tests/acceptance/test_FG_007_postgres-scratch-trixie.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
