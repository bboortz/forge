---
id: FG-033
slug: locale-utf8
status: draft
owner: bboortz
created: 2026-11-08
---

# FG-033 — Ship usable C.UTF-8 + en_US.UTF-8 locales in postgres-scratch + python-scratch

Both `postgres-scratch-trixie:18` and `python-scratch-trixie:3.14` set `ENV LANG=C.UTF-8` in their runtime stage — but neither image's runtime overlay ships `/usr/lib/locale/`. On startup, glibc's `setlocale(LC_ALL, "")` silently falls back to the `C` locale: postgres reports `lc_ctype=C` from `initdb`; python's `locale.setlocale(locale.LC_ALL, "C.UTF-8")` raises `locale.Error: unsupported locale setting`. The ENV is a lie.

FG-033 fixes both images by compiling two locales in the builder stage (`localedef -c -i C -f UTF-8 C.UTF-8` + `localedef -c -i en_US -f UTF-8 en_US.UTF-8`), COPYing `/usr/lib/locale/` into the runtime overlay, and locking the contract with smoke tests that exercise UTF-8-correct behavior end-to-end. Two locales — not one — so consumers get both byte-order (C.UTF-8) and Unicode-alphabetical (en_US.UTF-8) collation options without a derived image. Matches Docker Hub `postgres:18`'s default locale set.

## 9 canonical answers

1. **Who** — every `postgres-scratch-trixie` + `python-scratch-trixie` consumer with non-ASCII data. Homelab's nextcloud (Unicode filenames + usernames, ORDER BY sort behavior). Any i18n app running on either base. Operators auditing `lc_ctype` on postgres clusters.

2. **When** — fires at every `initdb` call (today silently coerces `--locale=C.UTF-8` → `C`); at every `locale.setlocale(...)` call in python code (today raises); at every `SELECT UPPER()`/`LENGTH()`/`ORDER BY` on non-ASCII strings. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `/usr/lib/locale/C.utf8/LC_CTYPE` + `/usr/lib/locale/en_US.utf8/LC_CTYPE` both present in each image (inspectable via `docker save | tar tf`).
   - Postgres: `initdb --locale=en_US.UTF-8` succeeds; `pg_controldata` reports `LC_COLLATE=en_US.UTF-8`; `SELECT UPPER('ä')` → `Ä`; `SELECT length('€')` → `1`; `ORDER BY` on `['ä','z','a']` returns `a, ä, z` (Unicode alphabetical, not byte order).
   - Python: `locale.setlocale(locale.LC_ALL, 'C.UTF-8')` + `locale.setlocale(locale.LC_ALL, 'en_US.UTF-8')` both succeed; `locale.strcoll('ä', 'z') < 0` under `en_US.UTF-8` and `> 0` under `C.UTF-8` — proves distinct collation behavior.
   - Image sizes stay within budgets (postgres ≤ 120 MB, python-scratch ≤ 60 MB). Two locales add ~2-3 MB combined.
   - grype scan stays clean.

4. **Urgency** — correctness. Current `ENV LANG=C.UTF-8` is misleading on both images; i18n data is silently misclassified / miscased / missorted. python-scratch's locale-dependent stdlib (`locale`, `string.capwords`, regex `\w` with `re.LOCALE`, etc.) silently misbehaves.

5. **Happy path**:
   1. Builder stages compile both locales with `localedef`.
   2. Runtime overlays include `/usr/lib/locale/`.
   3. Daily cron publishes updated images.
   4. Postgres consumers re-`initdb` with `--locale=C.UTF-8` or `--locale=en_US.UTF-8` on fresh data dirs (existing clusters don't auto-migrate — see § Edge cases).
   5. Python consumers call `locale.setlocale(locale.LC_ALL, 'en_US.UTF-8')` and get Unicode-aware behavior.

6. **Edge cases / failure modes**:
   - **Existing postgres clusters still have `LC_CTYPE=C` baked in.** `pg_controldata` of a cluster `initdb`'d by the pre-FG-033 image stays that way; postgres never re-reads locale. Migration: `pg_dumpall` → delete data dir → `initdb --locale=en_US.UTF-8` → reload.
   - **Image size cost**: `locales` package is already installed in postgres-scratch's builder; python-scratch's builder needs it added (new apt install). Shipping ONLY C.UTF-8 + en_US.UTF-8 keeps overhead to ~2-3 MB combined (full archive would be ~55 MB).
   - **glibc 2.35+ built-in C.UTF-8** — glibc has an internal C.UTF-8 that `setlocale` accepts even without a file. But: postgres `initdb` double-checks the filesystem; python's `locale.setlocale` on some distros also wants the file. Ship files for both — belt and suspenders.
   - **`locales` + `locale-gen` interaction** — using `localedef` directly (not the `locale-gen` wrapper) so we compile exactly the two locales we want. `locale-gen` with a bare `/etc/locale.gen` is a no-op; appending our locales first would work too but is a weaker contract.
   - **python-scratch builder apt layer** — adding `locales` to the apt install slightly grows the builder closure (which doesn't ship to the runtime). No runtime SBOM/scan impact from the package itself.

7. **Out of scope**:
   - Additional locales (de_DE, fr_FR, ja_JP.UTF-8, etc.). Consumers who need regional collation can build derived images. Two locales cover the "default minimal UTF-8" + "natural Unicode alphabetical" axis.
   - Fixing the same `ENV LANG=C.UTF-8` on **other** scratch images (nginx-scratch, redis-scratch, mosquitto-scratch). None of those currently set `ENV LANG`; they inherit from scratch-base-trixie's default (empty). No bug to fix there.
   - Auto-migrating existing postgres clusters. Consumer operation.
   - Changing the `ENV LANG` default on either image (stays `C.UTF-8`; now actually works).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.locale-utf8` — both postgres-scratch and python-scratch ship compiled C.UTF-8 + en_US.UTF-8 locales; `setlocale(LC_ALL, "C.UTF-8")` and `setlocale(LC_ALL, "en_US.UTF-8")` return non-NULL and the locale is honored downstream.
   - EXT `image.postgres-serves-sql` — now includes functional UTF-8 collation + case mapping (both locales), not just ASCII.
   - EXT `image.python-scratch-nonroot` — `locale.setlocale` with C.UTF-8 or en_US.UTF-8 no longer raises.

## Gherkin acceptance

```
Scenario: Both locales ship in postgres-scratch-trixie
  Given forge-local/postgres-scratch-trixie:18 is built
  When the image contents are inspected via `docker save | tar tf`
  Then /usr/lib/locale/C.utf8/LC_CTYPE is present
   And /usr/lib/locale/en_US.utf8/LC_CTYPE is present

Scenario: Both locales ship in python-scratch-trixie
  Given forge-local/python-scratch-trixie:3.14 is built
  When the image contents are inspected via `docker save | tar tf`
  Then /usr/lib/locale/C.utf8/LC_CTYPE is present
   And /usr/lib/locale/en_US.utf8/LC_CTYPE is present

Scenario: initdb --locale=en_US.UTF-8 produces an en_US.UTF-8 cluster
  Given a shelled sidecar + fresh data volume
  When the sidecar runs initdb --locale=en_US.UTF-8 /data
  Then initdb exits 0
   And `pg_controldata /data` reports LC_COLLATE=en_US.UTF-8
   And `pg_controldata /data` reports LC_CTYPE=en_US.UTF-8

Scenario: Postgres UTF-8 character length returns chars, not bytes
  Given a running postgres against an en_US.UTF-8 cluster
  When `psql -c "SELECT length('€')"` runs
  Then the result is 1
  When `psql -c "SELECT octet_length('€')"` runs
  Then the result is 3

Scenario: Postgres case transformation respects Latin-1 Supplement
  Given a running postgres against an en_US.UTF-8 cluster
  When `psql -c "SELECT UPPER('äöü')"` runs
  Then the result is ÄÖÜ

Scenario: Postgres Unicode collation sorts alphabetically, not byte-wise
  Given a running postgres against an en_US.UTF-8 cluster
  When `psql -c "SELECT val FROM (VALUES ('ä'), ('z'), ('a')) t(val) ORDER BY val"` runs
  Then the order is a, ä, z  # Unicode alphabetical — C.UTF-8 would produce a, z, ä (byte order)

Scenario: Python setlocale succeeds for both locales
  Given forge-local/python-scratch-trixie:3.14
  When the container runs `python3 -c "import locale; locale.setlocale(locale.LC_ALL, 'C.UTF-8')"`
  Then it exits 0
  When the container runs `python3 -c "import locale; locale.setlocale(locale.LC_ALL, 'en_US.UTF-8')"`
  Then it exits 0

Scenario: Python strcoll distinguishes the two locales
  Given forge-local/python-scratch-trixie:3.14
  When python3 runs strcoll('ä', 'z') under en_US.UTF-8
  Then the result is negative  # Unicode alphabetical
  When python3 runs strcoll('ä', 'z') under C.UTF-8
  Then the result is positive  # byte order

Scenario: No regression against existing postgres + python smokes
  Given FG-007 + FG-026 + FG-003 + FG-009 + FG-031 acceptance tests
  When they are re-run against the FG-033 images
  Then every assertion still passes

Scenario: Image sizes within budgets
  Given FG-033-rebuilt postgres-scratch-trixie + python-scratch-trixie
  Then postgres image size ≤ 120 MB
   And python image size ≤ 60 MB
```

## References

- Plan: `docs/plan/FG-033-locale-utf8-plan.md`
- Red test: `tests/acceptance/test_FG_033_locale-utf8.sh`
- Capabilities: see `docs/CAPABILITIES.md` (NEW `image.locale-utf8`, EXT `image.postgres-serves-sql`, EXT `image.python-scratch-nonroot`)
- Precedent: FG-007 (postgres sidecar-init), FG-026 (postgres 17→18), FG-003 (python-scratch runtime), FG-009 (python-scratch hardening)
