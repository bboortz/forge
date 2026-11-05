---
id: FG-015
slug: beaconry-telegram-mock
status: shipped
owner: bboortz
created: 2026-11-05
---

# FG-015 — Add beaconry-telegram-mock (externally-sourced test fixture)

Third and final beaconry image Forge takes over. **Test fixture**, not a production artifact — beaconry's `docker-compose.test.yml` uses this as an in-cluster Telegram API shim so hub's `python-telegram-bot` client can be exercised without hitting `api.telegram.org`.

Unlike scout/hub, this image is **NOT** `FROM python-scratch-trixie:3.13`. Upstream uses `FROM python:3.12-slim` — acceptable for a test fixture (operators never deploy this to production). Consequence: no `absence.shell` + no `absence.os-cves` promise. Forge still attaches the grype scan attestation so operators can inspect, but we don't contract-level assert zero OS CVEs — that'd require Dockerfile changes we don't own.

## 9 canonical answers (compressed)

1. **Who** — Beaconry integration-test consumers who want the mock image pulled from a signed Forge digest; auditors reviewing the test stack.
2. **When** — on every PR / pre-push / daily cron; `ref: latest` tracks beaconry main.
3. **Success** — `ghcr.io/bboortz/beaconry-telegram-mock:0.1` publishes; HTTP server on :8080 responds to `/bot<token>/getMe` + `/__driver__/state`; `revision` label = upstream HEAD sha.
4. **Urgency** — quality-of-life. Not blocking.
5. **Happy path** —
   1. `images/beaconry-telegram-mock/image.yaml` — source.git + ref: latest + dockerfile: poc/telegram_mock/Dockerfile + context: poc. NO `depends_on:` (no Forge image dep; FROMs upstream `python:3.12-slim`).
   2. `PROMISES.yaml` — 3 promises: runtime.http-server, runtime.driver-endpoints (BC-018 injection API), shape.size-budget (≤ 300 MB).
   3. **No `EXPECTATIONS.yaml`** — no Forge dependency (verify-contracts allows this when `depends_on:` is absent).
   4. 3 smokes: smoke_http_mock.sh (getMe 200), smoke_driver_api.sh (/__driver__/state 200), smoke_size.sh.
   5. FG-015 acceptance test.
6. **Edge cases** —
   - Upstream Dockerfile has no apt-upgrade → grype finds Debian-source CVEs. Not a promise we make; attestation still attached.
   - Mock responds to ANY bearer token prefix (`/bot<anything>/...`); smoke uses a fixed test token string.
7. **Out of scope** —
   - Promoting telegram_mock to a scratch base. Owner's choice; stays slim as long as upstream does.
   - Zero-OS-CVE promise (incompatible with a slim-based image we don't own).
8. **Done** — FG-015 acceptance + `make check-strict` green.
9. **Capabilities**:
   - NEW `image.beaconry-telegram-mock` — Forge-published mock
   - EXT `build.external-source` — third consumer (proves mechanism is base-agnostic — not just python-scratch derivatives)

## Gherkin acceptance

```
Scenario: mock boots + serves getMe
  Given forge-local/beaconry-telegram-mock:0.1
  When the container runs
  Then GET /bot<any-token>/getMe returns 200

Scenario: driver API is reachable
  Given the running mock
  When GET /__driver__/state
  Then it returns 200 (BC-018 test driver surface)

Scenario: image labels pin upstream provenance
  Given ref: latest
  Then org.opencontainers.image.revision is a 40-char sha
   And org.opencontainers.image.source = https://github.com/bboortz/beaconry
```

## References

- Plan: [`docs/plan/FG-015-beaconry-telegram-mock-plan.md`](../plan/FG-015-beaconry-telegram-mock-plan.md)
- Red test: [`tests/acceptance/test_FG_015_beaconry-telegram-mock.sh`](../../tests/acceptance/test_FG_015_beaconry-telegram-mock.sh)
- Upstream: `bboortz/beaconry@main` → `poc/telegram_mock/Dockerfile`
