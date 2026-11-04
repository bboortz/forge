# FG-007 — Plan: postgres-scratch-trixie

**Story**: [`docs/stories/FG-007-postgres-scratch-trixie.md`](../stories/FG-007-postgres-scratch-trixie.md)
**Status**: shipped (pending post-publish evidence)
**Branch**: `feat/FG-007-postgres-scratch-trixie`

## Design delta

Third scratch image. Two-stage Dockerfile; builder installs `postgresql-17 postgresql-client-17 ca-certificates`; runtime `FROM scratch` copies in a curated subset:

- 9 binaries (postgres, initdb, pg_ctl, pg_isready, psql, pg_dump, pg_restore, pg_config, pg_dumpall) — no Debian wrapper scripts.
- `/usr/lib/postgresql/17/lib/` — postgres' private shared libs (plpgsql, built-in extensions).
- `/usr/share/postgresql/17/` — timezone sets, locale, encoding converters, extension SQL. ~30 MB.
- Full dlopen closure of the above (~50 shared libs: glibc, ICU, krb5, LDAP, PAM, OpenSSL, libxml2, readline, systemd, cap, audit, stdc++).
- `postgres` user pinned to **uid 999** / **gid 999** matching Docker Hub's convention — crucial for cluster-directory compatibility with volumes initialized by other postgres images.
- `PGDATA=/var/lib/postgresql/data`, `PATH=/usr/lib/postgresql/17/bin`, `USER postgres`. `CMD ["postgres"]` so `docker run <image>` starts the server (will error without a data dir, expected).

No LLVM JIT (postgresql-17-jit omitted). ~100 MB saved; consumers who need JIT add it themselves.

## Alternatives rejected

- **Bake a pre-initialized cluster into the image** — lets scratch users skip the sidecar for init. Downside: fixed locale, fixed superuser password (none), surprise for consumers who expected an uninitialized image. Cleaner to document the sidecar pattern.
- **Include `/bin/sh` (busybox or dash)** — ~130 KB, makes initdb work in-scratch, but breaks the "no shell" differentiator that's the whole point of scratch. Non-starter.
- **Use `apt install postgresql` (meta-package pulling perl + pg_ctlcluster wrappers)** — adds Debian cluster-management layer that fights against our simpler model. Direct `postgresql-17` + `postgresql-client-17` is honest.
- **Include LLVM JIT** — ~100 MB for marginal benefit. Consumers who need it extend this image.
- **Trust dynamically-assigned postgres UID** — brittle; Docker Hub pins to 999 and that's the conventional expectation. Hardcode 999.

## Breaking changes

None (new image).

## Merge plan

Fast tier (local `make check-strict`): lint, verify-sid-pins, verify-traceability, test-acceptance (incl. FG-001–007), test-images (now 25 scripts across 4 variants). Pre-push + CI run the same.

The FG-007 smoke suite downloads `postgres:17` from Docker Hub on first run (~160 MB one-time); CI runners cache this across jobs via actions/cache if we add it later. For now it's an unconditional pull on cold CI runs — acceptable.

## Rollout plan

Standard: merge to dev → release.yml → build.yml matrix auto-enrolls postgres-scratch-trixie (per FG-003 publish.matrix-auto-discovery). GHCR package visibility flip once on first publish. For this autonomous run: merge to dev only; operator triggers release+publish later.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: postgres --version | `images/postgres-scratch-trixie/tests/smoke_binary_runs.sh` | ✅ |
| Scenario: scratch postgres serves SELECT 1 | `images/postgres-scratch-trixie/tests/smoke_server_accepts.sh` | ✅ |
| Scenario: no shell | `images/postgres-scratch-trixie/tests/smoke_no_shell.sh` | ✅ |
| Scenario: zero Debian-source CVEs | `images/postgres-scratch-trixie/tests/smoke_zero_os_cves.sh` | ✅ |
| Scenario: size ≤ 150 MB | `images/postgres-scratch-trixie/tests/smoke_size.sh` (SIZE_CEILING=150_000_000) | ✅ |
| Scenario: postgres uid = 999 | `images/postgres-scratch-trixie/Dockerfile` (pg_uid=999 pin) + FG-007 acceptance | ✅ |
| CAP `image.postgres-serves-sql` | smoke_server_accepts.sh + `docs/CAPABILITIES.md` | ✅ |
| CAP `test.sidecar-init` | smoke_server_accepts.sh (init via postgres:17 sidecar) + `docs/CAPABILITIES.md` | ✅ |
| EXT `image.no-shell` | smoke_no_shell.sh | ✅ |
| EXT `image.zero-os-cves` | smoke_zero_os_cves.sh | ✅ |
| EXT `test.size-budget` | smoke_size.sh 150 MB ceiling | ✅ |
| Scenario: cosign verify (post-publish) | FG-007 acceptance PUBLISHED=1 | ⚠️ post-publish |
| Scenario: GHCR anonymous pull (post-publish) | GHCR package visibility flip | ⚠️ post-publish |

Local measurements: image size **104 MB** (69 % of 150 MB ceiling); grype reports 7 total matches, **0** Debian/dpkg-source; initdb-via-postgres:17-sidecar + scratch-postgres + scratch-psql `SELECT 1` round-trip succeeds end-to-end.
