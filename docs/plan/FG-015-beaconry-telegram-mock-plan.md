# FG-015 — Plan: beaconry-telegram-mock

**Story**: [`docs/stories/FG-015-beaconry-telegram-mock.md`](../stories/FG-015-beaconry-telegram-mock.md)
**Status**: shipped
**Branch**: `feat/FG-015-beaconry-telegram-mock`

## Design delta

```
images/beaconry-telegram-mock/
  image.yaml      — source.git=bboortz/beaconry, ref=latest, dockerfile=poc/telegram_mock/Dockerfile, context=poc. NO depends_on.
  PROMISES.yaml   — 3 promises (no absence.shell, no absence.os-cves — slim base, test fixture)
  tests/
    smoke_http_mock.sh     — curl /bot<token>/getMe → 200
    smoke_driver_api.sh    — curl /__driver__/state → 200 (BC-018 surface)
    smoke_size.sh          — ≤ 300 MB
```

**No `EXPECTATIONS.yaml`** — telegram_mock FROMs upstream `python:3.12-slim`, not a Forge image. `verify-contracts` allows missing EXPECTATIONS when `image.yaml` has no `depends_on:`.

## Alternatives rejected

- **Promote the Dockerfile to `FROM python-scratch-trixie:3.13`**: would require upstream Dockerfile changes we don't own; also complicates the test-fixture story (devs expect compose-dev to just work with simple shelled images).
- **Promise `absence.os-cves`**: incompatible without Dockerfile-level apt-upgrade which we don't control. Forge still attaches the grype scan attestation — operators can read it.
- **Skip this image entirely**: user explicitly asked to take over "all images we might need" and the mock is one of three beaconry Dockerfiles.

## Breaking changes

None. New image dir.

## Merge plan

Single PR. Pre-push `make check-strict`.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: /bot/getMe 200 | `images/beaconry-telegram-mock/tests/smoke_http_mock.sh` | ⏳ |
| Scenario: /__driver__/state 200 | `smoke_driver_api.sh` | ⏳ |
| Scenario: OCI labels pin upstream | FG-015 acceptance § section 3 | ⏳ |
| NEW CAP `image.beaconry-telegram-mock` | CAPABILITIES.md | ⏳ |
| `make check-strict` green | local | ⏳ |
