# FG-033 — Plan: C.UTF-8 + en_US.UTF-8 in postgres-scratch + python-scratch

**Story**: [`docs/stories/FG-033-locale-utf8.md`](../stories/FG-033-locale-utf8.md)
**Status**: shipped
**Branch**: `feat/FG-033-locale-utf8`

## Design delta

### Shared pattern

Both builders: install `locales` (postgres already has it; python needs it added), run `localedef -c -i C -f UTF-8 C.UTF-8` + `localedef -c -i en_US -f UTF-8 en_US.UTF-8`, verify compile via `locale -a | grep`, then COPY the resulting `/usr/lib/locale/C.utf8/` + `/usr/lib/locale/en_US.utf8/` + `/usr/lib/locale/locale-archive` into the runtime overlay. `localedef` (not `locale-gen`) so we compile exactly the two locales we want; avoids the ~55 MB whole-archive bloat.

### `images/postgres-scratch-trixie/Dockerfile`

- After the existing `apt-get install ... locales ...` block, add:

```dockerfile
# FG-033: compile the two UTF-8 locales we promise in PROMISES. Using
# localedef (not locale-gen) so we get exactly these two locales and no
# more — full locale-gen would bloat the archive by ~55 MB.
RUN set -eux; \
    localedef -c -i C     -f UTF-8 C.UTF-8; \
    localedef -c -i en_US -f UTF-8 en_US.UTF-8; \
    locale -a | grep -qx C.utf8; \
    locale -a | grep -qx en_US.utf8
```

- Extend the overlay-assembly `RUN` to stage the locales:

```dockerfile
install -d /out/usr/lib/locale; \
cp -r /usr/lib/locale/C.utf8     /out/usr/lib/locale/C.utf8; \
cp -r /usr/lib/locale/en_US.utf8 /out/usr/lib/locale/en_US.utf8; \
cp /usr/lib/locale/locale-archive /out/usr/lib/locale/locale-archive 2>/dev/null || true;
```

### `images/python-scratch-trixie/Dockerfile`

- Builder stage currently doesn't apt-install anything beyond what forge-builder-trixie ships. Add a dedicated locale install + compile step, bracketed to not grow forge-builder-trixie itself:

```dockerfile
# FG-033: install locales for localedef, compile C.UTF-8 + en_US.UTF-8,
# then purge the locales package (we only need the binary artifacts in
# /usr/lib/locale, not the apt-tracked package).
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install locales; \
    localedef -c -i C     -f UTF-8 C.UTF-8; \
    localedef -c -i en_US -f UTF-8 en_US.UTF-8; \
    locale -a | grep -qx C.utf8; \
    locale -a | grep -qx en_US.utf8; \
    apt-get -y purge locales; \
    apt-get -y --purge autoremove; \
    rm -rf /var/lib/apt/lists/*
```

(Note: `localedef`'s output under `/usr/lib/locale/` survives the `apt purge locales` because dpkg doesn't track those paths — they're generated post-install by `localedef`.)

- Extend the builder's `/out` staging `RUN` to COPY `/usr/lib/locale/` (same pattern as postgres).

### Smoke tests

**`images/postgres-scratch-trixie/tests/smoke_locale_utf8.sh`** (new):
1. Content check via `docker save | tar tf` — both `usr/lib/locale/C.utf8/LC_CTYPE` and `usr/lib/locale/en_US.utf8/LC_CTYPE` present.
2. Runtime behavior via FG-007 `test.sidecar-init` pattern: shelled sidecar (`docker.io/postgres:18`) runs `initdb --locale=en_US.UTF-8` → scratch image serves against that volume; psql probes:
   - `SELECT length('€')` == 1
   - `SELECT octet_length('€')` == 3
   - `SELECT UPPER('äöü')` == `ÄÖÜ`
   - `SELECT val FROM (VALUES ('ä'),('z'),('a')) t(val) ORDER BY val` → `a, ä, z` (Unicode alphabetical)
   - `pg_controldata` of the data dir reports `LC_COLLATE=en_US.UTF-8` + `LC_CTYPE=en_US.UTF-8`

**`images/python-scratch-trixie/tests/smoke_locale_utf8.sh`** (new):
1. Content check — both locale dirs present in the image.
2. Runtime behavior:
   - `python3 -c "import locale; locale.setlocale(locale.LC_ALL, 'C.UTF-8')"` → exit 0
   - `python3 -c "import locale; locale.setlocale(locale.LC_ALL, 'en_US.UTF-8')"` → exit 0
   - Distinguishing strcoll: under `en_US.UTF-8`, `strcoll('ä', 'z') < 0`; under `C.UTF-8`, `strcoll('ä', 'z') > 0`.

### Acceptance test (`tests/acceptance/test_FG_033_locale-utf8.sh`)

4 sections:
1. Static invariants — both Dockerfiles carry `localedef ... C.UTF-8` + `localedef ... en_US.UTF-8`; both PROMISES.yaml carry `runtime.locale-utf8`; both smoke scripts exist + are executable; CAPABILITIES.md has `image.locale-utf8`.
2. Build both images.
3. Run `smoke_locale_utf8.sh` on each image + the rest of their existing suites (regression guard).
4. Re-run acceptance tests for FG-003, FG-007, FG-009, FG-026, FG-031 against the new images.

### PROMISES.yaml bumps

- `postgres-scratch-trixie`: version `0.2` → `0.3`; add `runtime.locale-utf8` promise (caps `image.locale-utf8`, `image.postgres-serves-sql`).
- `python-scratch-trixie`: version `0.3` → `0.4`; add `runtime.locale-utf8` promise (caps `image.locale-utf8`, `image.python-scratch-nonroot`).

### `docs/CAPABILITIES.md`

- NEW: `image.locale-utf8` entry — describes the two compiled locales + the glibc `setlocale` contract.
- EXT: `image.postgres-serves-sql` + `image.python-scratch-nonroot` — short "FG-033 extended by…" notes.

### No workflow changes

`build.yml` + `ci.yml` + `release.yml` all unchanged.

## Alternatives rejected

- **Only C.UTF-8** — covers minimum UTF-8 correctness but gives byte-order collation (`a, z, ä`) for ORDER BY on non-ASCII. Shipping en_US.UTF-8 alongside adds Unicode-alphabetical sort (`a, ä, z`) for ~1.5 MB. Trivial cost; concrete value for homelab's filename/username sorts.
- **Add locales to scratch-base-trixie** — would propagate to all five scratch images in one edit. Rejected: nginx-scratch / redis-scratch / mosquitto-scratch don't exercise locale-dependent behavior and don't set `ENV LANG`. Baseline follows strict-intersection; adding ~2.5 MB for two consumers that need it violates that. Keep it per-image.
- **Run `locale-gen` with an appended `/etc/locale.gen`** — writes the whole archive; `localedef` per locale gives us tight control over which locales ship.
- **Drop `ENV LANG=C.UTF-8` from the Dockerfiles** — makes the bug self-honest but loses the (eventual) UTF-8 semantics. Fixing is strictly better.
- **Different default locale** (e.g. `en_US.UTF-8` as the baked `ENV LANG`) — matches Docker Hub postgres but changes a public contract. Stay on `C.UTF-8` (now working); consumers who want `en_US.UTF-8` set `ENV LANG=en_US.UTF-8` in their derived Dockerfile. Minimal-surprise upgrade.

## Breaking changes

- **Existing postgres cluster data dirs** initialized by pre-FG-033 images carry `LC_CTYPE=C` and can't be changed in place. Consumers wanting UTF-8 collation on existing clusters: `pg_dumpall` → delete data dir → `initdb --locale=en_US.UTF-8` (or `C.UTF-8`) → reload. Documented in README migration note.
- **Image sizes**: postgres +~2 MB (both locales), python +~2 MB. Both well under budgets.
- No change to: ENV vars, cosign identity, GHCR repo names, attestation format, FG-007 sidecar-init pattern, FG-026 postgres version, FG-031 `/hc` embed, FG-032 Python 3.14 version.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass.
- FG-033 red acceptance test green (all 4 sections).
- FG-003 / FG-007 / FG-009 / FG-026 / FG-031 regression re-runs green.
- `make test-fast` + `make check` clean locally.
- `scan-baseline.json` regenerated for both images if dpkg closure drifts (postgres already has `locales`; python's new apt install gets purged before the SBOM scan, so no runtime closure change expected — verify and regen if needed).

## Rollout plan

1. Land FG-033 on `dev` via PR. CI uses forge-local builds — no external consumer impact.
2. Promote to `main` via `release.yml` dispatch.
3. Next 03:00 UTC cron publishes both `:latest` images with locales baked in. Internal consumers (beaconry-hub, beaconry-scout) rebuild against the new `python-scratch-trixie:latest` — no breakage expected because adding `/usr/lib/locale/` only ADDS paths, doesn't change any existing paths.
4. README `§ Images` table updated with the "existing postgres clusters need dump/reinit for UTF-8" migration note.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: Both locales ship in postgres | `tests/acceptance/test_FG_033_locale-utf8.sh` § 3 + smoke_locale_utf8.sh | ⏳ |
| Scenario: Both locales ship in python | § 3 + python smoke | ⏳ |
| Scenario: initdb --locale=en_US.UTF-8 works | § 3 (sidecar-init) | ⏳ |
| Scenario: length('€') == 1 | § 3 (psql probe) | ⏳ |
| Scenario: UPPER('äöü') == ÄÖÜ | § 3 (psql probe) | ⏳ |
| Scenario: ORDER BY gives Unicode alphabetical | § 3 (psql probe) | ⏳ |
| Scenario: Python setlocale succeeds for both | § 3 (python smoke) | ⏳ |
| Scenario: Python strcoll distinguishes locales | § 3 (python smoke) | ⏳ |
| Scenario: FG-003/007/009/026/031 regression | § 4 (re-runs) | ⏳ |
| Scenario: Image sizes within budgets | smoke_size.sh in each image | ⏳ |
| NEW CAP `image.locale-utf8` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
| EXT `image.postgres-serves-sql` + `image.python-scratch-nonroot` | CAPABILITIES edits + acceptance | ⏳ |
