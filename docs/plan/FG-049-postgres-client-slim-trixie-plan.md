# FG-049 — Plan: postgres-client-slim-trixie

**Story**: [`docs/stories/FG-049-postgres-client-slim-trixie.md`](../stories/FG-049-postgres-client-slim-trixie.md)
**Status**: ready → (pending implementation — story + plan + red test land first, implementation paused for user review)
**Branch**: `feat/FG-049-postgres-client-slim-trixie`

## Working solution ships today without this story

**`postgres-slim-trixie:18` (FG-026) already solves the pg_dumpall / initdb / pg_amcheck workflow** at 438 MB. It's `FROM postgres:18` (Docker Hub, externally-maintained-runtime exemption from `memory/docker-standard.md`), apt-upgraded, with `/bin/sh`. The 2026-11-10 operator confusion is resolved by the parallel doc-only commit that extends postgres-scratch-trixie's `absence.shell` PROMISE description to point operators at FG-026 as the sibling. **FG-049 is the optional smaller forge-rooted follow-up.** Ship this story when:

- Multiple operators independently hit the 438 MB sidecar weight as inconvenient (e.g. across many homelab hosts, pulls add up), OR
- A new postgres-based sidecar (e.g. barman, repmgr, pgbackrest) lands and would benefit from sharing a lean client base, OR
- Beaconry / scan tooling flags postgres-slim-trixie's scan surface as too noisy for backup use cases.

Until one of those triggers fires, the postgres-scratch doc fix is sufficient.

## Design delta

### `images/postgres-client-slim-trixie/` (new — not yet shipped)

- `image.yaml`: `tag: "18"` (matches postgres-scratch-trixie's version pin), platforms `[linux/amd64]`. **No `depends_on`** — slim variant consumes debian-slim-trixie at runtime via `FROM`, not via scratch-base overlay composition. (Precedent: cadvisor-slim-trixie, ipmi-exporter-slim-trixie — both FG-042 consumers of debian-slim-trixie use the FROM-only pattern.)
- `Dockerfile`: two-stage (builder for scan surface + runtime for shipping).
  - Stage 0: `FROM docker.io/anchore/syft:latest AS syft-src` (syft binary — FG-025 convention; subject to FG-047 pin follow-up).
  - Stage 1 (builder): `FROM ghcr.io/bboortz/forge-builder-trixie AS builder` — add the PGDG apt source, install `postgresql-client-18` + `libnss-db` + `locales`, emit SBOM via syft against the dpkg state.
  - Stage 2 (runtime): `FROM ghcr.io/bboortz/debian-slim-trixie` — add the PGDG apt source, install `postgresql-client-18` + `locales`, pin postgres uid 999 (`useradd -u 999 -r -s /bin/sh postgres`), set PATH to include `/usr/lib/postgresql/18/bin`, USER 999:999, no ENTRYPOINT (toolkit — operator supplies the binary per invocation), CMD defaults to `["psql", "--help"]` for a friendly bare-run.
  - Deliberate: `postgresql-client-18` pulls in `postgresql-common` + `perl-base` (both present in debian-slim-trixie already from apt-upgrade). This is fine — slim contract allows the Debian package metadata to exist.
- `PROMISES.yaml`: 8 promises covering the 4 NEW CAPs + extensions (`runtime.pg-client-tools`, `runtime.pg_dumpall-works-e2e`, `absence.pg-server-binaries` (inverse), `presence.shell`, `identity.postgres-uid`, `shape.size-budget`, `scan.nonzero-accepted`, `runtime.pg-client-nonroot`). `version: "0.1"`.
- **No `EXPECTATIONS.yaml`** — slim variant, no scratch-base contract.
- `scan-baseline.json` — regenerated per-build. Expected nonzero CVE set (unlike scratch which promises zero). Shape mirrors cadvisor-slim-trixie's baseline.
- `sid-pins/` — empty at creation; follow the same pin-when-needed pattern as postgres-scratch-trixie.

### Chain depth check (FG-042 invariant ≤ 5)

- `debian:trixie-slim` (Docker Hub) → `debian-slim-trixie` (forge pre-builder) → `postgres-client-slim-trixie` (this image) = **3 hops**.
- Well within the ≤ 5 ceiling. No chain-depth concern.

### Why FROM debian-slim-trixie (not FROM postgres-scratch-trixie + add shell)

- postgres-scratch-trixie's whole point is absence-of-shell. Deriving from it and adding a shell inverts the parent's contract, breaks its PROMISES on any derivative, and mixes two mutually-exclusive design goals.
- debian-slim-trixie already carries the apt-upgrade + CA + shell + uid conventions we want. Dogfood it (FG-042's purpose).
- Keeps server + client responsibilities as sibling images with a single reusable base, not a derivation chain.

### Why postgresql-client-18 from PGDG (same channel as postgres-scratch-trixie)

Scratch and slim MUST agree on major version + minor bump cadence so that a pg_dumpall produced by the slim client replays cleanly into the scratch server. Single PGDG channel + same minor version per cron re-resolve guarantees that.

### Smoke suite (`images/postgres-client-slim-trixie/tests/`)

Six scripts — mirrors the shape of other slim images (cadvisor-slim-trixie, ipmi-exporter-slim-trixie):

- `smoke_client_binaries_run.sh` — every one of pg_dump, pg_dumpall, pg_restore, psql, pg_basebackup, pg_receivewal, pg_amcheck, pg_isready reports --version.
- `smoke_pg_dumpall_e2e.sh` — boots a `postgres:18` Docker Hub sidecar (same pattern as postgres-scratch-trixie's smoke_server_accepts), runs pg_dumpall from the forge client image, asserts the output contains a CREATE DATABASE line.
- `smoke_no_server_binaries.sh` — asserts postgres, initdb, pg_ctl are NOT present. Prevents accidental bloat.
- `smoke_has_shell.sh` — /bin/sh present + echoes.
- `smoke_user_postgres.sh` — uid 999 as default.
- `smoke_size.sh` — ≤ 200 MB hard ceiling.

Co-located convention per `memory/docker-standard.md` § "Per-image smoke tests".

### Red acceptance test — `tests/acceptance/test_FG_049_postgres-client-slim-trixie.sh`

5 sections, following FG-045's structure:

1. **Required files** — Dockerfile, image.yaml, PROMISES.yaml, scan-baseline.json, 6 smokes present + executable. No EXPECTATIONS.yaml.
2. **Build** — `bash scripts/build-image.sh postgres-client-slim-trixie` succeeds.
3. **Smoke suite** — all 6 smokes green (including E2E pg_dumpall).
4. **image.yaml invariants** — tag=18, platforms=[linux/amd64], no depends_on.
5. **Sibling link check** — postgres-scratch-trixie's PROMISES.yaml absence.shell description mentions "postgres-client-slim-trixie" (asserted via grep).

### `docs/CAPABILITIES.md` entries (added)

- NEW `image.postgres-client-tools`
- NEW `image.postgres-client-pg_dumpall-works`
- NEW `image.postgres-client-no-server`
- NEW `image.postgres-client-nonroot`
- EXT `image.has-shell` → add postgres-client-slim-trixie

### `docs/stories/INDEX.md`

New row for FG-049.

### `docs/plan/IDEAS.md`

- No new IDEAS entries unlocked by this story.
- The "node-slim-trixie + postgres-slim-trixie dogfood renewal" entry remains open — this story's postgres-client-slim-trixie is a *client toolkit*, not the "postgres-slim-trixie" pre-builder tracked in that idea. Different concern.

### Parallel doc-only fix (shipped alongside the red test, before implementation)

Separate commit on the same branch:

- `images/postgres-scratch-trixie/PROMISES.yaml`: extend `absence.shell` description to explicitly list `pg_dumpall`, `initdb`, `pg_amcheck` as present-but-unusable-standalone; reference postgres-client-slim-trixie as the sibling for those workflows.
- `images/postgres-scratch-trixie/tests/smoke_pg_dumpall_requires_shell.sh` — NEW smoke locking in the current ENOENT behavior (asserts the exact error message is produced). Prevents silent regression where some future change accidentally makes pg_dumpall work without a shell (e.g. ships a shell in the baseline).

## Alternatives rejected

- **Add /bin/sh to postgres-scratch-trixie** — breaks the differentiator-grade `absence.shell` promise + `smoke_no_shell.sh` test + the project's "no shell → no shell-based CVE class" story.
- **Static popen-shim /bin/sh** — tempting but adds a custom security surface (parsing shell quote rules); needs its own FG + review.
- **Ship-nothing — just use postgres-slim-trixie:18 (FG-026)** — this IS the alternative that ships today, via the parallel doc-only fix on postgres-scratch-trixie. FG-049 is the "if we want a smaller forge-rooted sibling" follow-up, not a replacement. If this story never ships, that's fine — the operator-facing bug is already addressed. Keep FG-049 drafted so the design is ready to go when a trigger fires.
- **Reuse postgres-slim-trixie:18 as the client (no new image)** — the chosen path for today. Downsides: operator pulls ~438 MB per backup host vs ~150-200 MB with FG-049; role is "server image repurposed as client" rather than "dedicated client toolkit."
- **Derive FROM postgres-scratch-trixie + add shell** — inverts parent's contract. Dogfooding debian-slim-trixie is cleaner.
- **Use Docker Hub's `postgres:18` as the client** — works, but not forge-signed, not Debian-apt-upgraded, not on our supply chain. (Note: FG-026 postgres-slim-trixie is exactly "forge-signed `postgres:18` + apt-upgrade", so this problem is already solved for the server-image-as-client reuse path.)
- **Only ship pg_dump + pg_dumpall** (minimal client) — operators who then want pg_restore or psql have to pull another image. Just ship the full `postgresql-client-18` package; marginal size difference.

## Breaking changes

None.

- New image, no existing consumers.
- No API change to postgres-scratch-trixie; only adds to its PROMISES description (expands what was already documented).
- No change to shared capabilities.

## Merge plan

Standard blocking gates (per `memory/workflow.md` § Blocking gates):

- hadolint + shellcheck + yamllint + actionlint all clean on new files.
- `make verify-sid-pins` — N/A (no sid pins at creation).
- `make verify-traceability` — new CAPs registered in CAPABILITIES.md with bidirectional test links.
- `make verify-contracts` — new PROMISES.yaml validates against schema.
- `make verify-no-upstream-drift` — unchanged (new image FROMs debian-slim-trixie, not an upstream anchor).
- `make test-acceptance` — new FG-049 test green.
- `make build` — succeeds from clean cache.
- `make scan` — grype attaches results; scan-baseline.json established.
- `make verify` — cosign verify (local key) green.
- Image size ≤ 200 MB.

## Rollout plan

1. Land story + plan + red test on `feat/FG-049-postgres-client-slim-trixie`. **Pause here per user instruction** (ship FG-049 story + plan, stop before implementation).
2. (On user go-ahead) Implement image + smokes + CI wiring + scan-baseline + PROMISES/EXPECTATIONS, turn red test green, PR to dev.
3. Autonomous merge on green CI per workflow.md step 8.
4. Promote to main via `release.yml` (user triggers).
5. Daily cron publishes `:18` + `:18-amd64` + `:latest` + `:latest-amd64`.
6. Operator wires a backup sidecar in homelab compose referencing `:18`.

## Shipping evidence

Filled at pre-ship audit (step 6a). One row per Gherkin scenario + one per CAP. Status: ⚠️ pending implementation, ✅ for story/plan/red-test artifacts that ship now.

| Item | Pointer | Status |
|------|---------|--------|
| Story drafted | `docs/stories/FG-049-postgres-client-slim-trixie.md` | ✅ |
| Plan drafted | `docs/plan/FG-049-postgres-client-slim-trixie-plan.md` | ✅ |
| Red acceptance test | `tests/acceptance/test_FG_049_postgres-client-slim-trixie.sh` | ✅ |
| INDEX.md updated | `docs/stories/INDEX.md` | ✅ |
| Doc-only fix on postgres-scratch-trixie | `images/postgres-scratch-trixie/PROMISES.yaml` + `smoke_pg_dumpall_requires_shell.sh` | ✅ |
| Scenario: publishes with triple | `tests/acceptance/test_FG_049_...sh` § 2 | ⚠️ |
| Scenario: every client binary runs standalone | § 3 + smoke_client_binaries_run.sh | ⚠️ |
| Scenario: pg_dumpall E2E | § 3 + smoke_pg_dumpall_e2e.sh | ⚠️ |
| Scenario: server binaries absent | § 3 + smoke_no_server_binaries.sh | ⚠️ |
| Scenario: shell present | § 3 + smoke_has_shell.sh | ⚠️ |
| Scenario: runs as uid 999 | § 3 + smoke_user_postgres.sh | ⚠️ |
| Scenario: size ≤ 200 MB | § 3 + smoke_size.sh | ⚠️ |
| Scenario: PATH env sane | § 3 + smoke_client_binaries_run.sh (default-PATH probe) | ⚠️ |
| Scenario: absence.shell cross-reference | § 5 (grep postgres-scratch PROMISES) | ✅ (doc-only fix committed before impl) |
| Scenario: co-use scratch server + slim client | § 3 + smoke_pg_dumpall_e2e.sh (uses scratch-like sidecar) | ⚠️ |
| NEW `image.postgres-client-tools` | `docs/CAPABILITIES.md` + smoke_client_binaries_run.sh | ⚠️ |
| NEW `image.postgres-client-pg_dumpall-works` | `docs/CAPABILITIES.md` + smoke_pg_dumpall_e2e.sh | ⚠️ |
| NEW `image.postgres-client-no-server` | `docs/CAPABILITIES.md` + smoke_no_server_binaries.sh | ⚠️ |
| NEW `image.postgres-client-nonroot` | `docs/CAPABILITIES.md` + smoke_user_postgres.sh | ⚠️ |
| EXT `image.has-shell` → postgres-client-slim-trixie | `docs/CAPABILITIES.md` extension | ⚠️ |
