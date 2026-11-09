---
id: FG-036
slug: alertmanager-scratch-trixie
status: draft
owner: bboortz
created: 2026-11-08
---

# FG-036 — alertmanager-scratch-trixie

New Forge image: `ghcr.io/bboortz/alertmanager-scratch-trixie:0.28` — Prometheus Alertmanager 0.28.1 (from Debian trixie's `prometheus-alertmanager` apt package), `FROM scratch` runtime via `scratch-base-trixie`. Enables homelab's alert routing with a signed/scanned/attested Forge base replacing `prom/alertmanager:latest`.

Alertmanager initiates outbound TLS for **every** notification receiver: Telegram bot API (`https://api.telegram.org`), Slack / Discord / Mattermost webhooks, email over SMTPS, generic HTTPS `webhook_configs`. The CA bundle at `/etc/ssl/certs/ca-certificates.crt` ships via `scratch-base-trixie`, but the Dockerfile must re-declare `ENV SSL_CERT_FILE` per the FG-009 lesson — otherwise every webhook fails with `x509: certificate signed by unknown authority`.

## 9 canonical answers

1. **Who** — homelab operator (me) routing alerts from prometheus → Telegram / Mattermost / email. Secondary: any Forge consumer wanting a signed Alertmanager.

2. **When** — fires at every alertmanager boot (compose up); at every alert received from prometheus; at every outbound notification. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/alertmanager-scratch-trixie:0.28` publishes daily with cosign + SBOM + scan attestations.
   - `docker run -v $(pwd)/alertmanager.yml:/etc/alertmanager/alertmanager.yml -p 9093:9093 <image>` boots a running instance.
   - `curl http://localhost:9093/-/healthy` returns HTTP 200.
   - `curl http://localhost:9093/-/ready` returns HTTP 200 after warmup.
   - Outbound HTTPS to a public webhook endpoint (e.g. `https://httpbin.org/post`) succeeds without `x509` errors — proves CA bundle resolved via re-declared `SSL_CERT_FILE`.
   - `amtool` ships in the image and can be invoked via `docker exec <container> /usr/bin/amtool check-config /etc/alertmanager/alertmanager.yml`.
   - Image size ≤ 100 MB.
   - grype reports zero Debian-source matches.
   - Homelab compose line swap: `image: prom/alertmanager:latest` → `image: ghcr.io/bboortz/alertmanager-scratch-trixie:0.28`. Volume + port unchanged.

4. **Urgency** — quality-of-life + supply-chain. Alerts are operator-critical; running a daily-rebuilt signed image gives faster patch cadence against Debian's security tracker.

5. **Happy path**:
   1. Forge daily cron publishes `:0.28` + `:latest`.
   2. Homelab compose updates `image:`.
   3. Alertmanager boots with existing `alertmanager.yml` + persistent storage (if any).
   4. Prometheus `alerting.alertmanagers` keeps pointing at `:9093` without change; webhooks continue firing.

6. **Edge cases / failure modes**:
   - **Persistent data dir** — alertmanager uses `/alertmanager/` by default for silences + notification history. Owned nonroot in the Forge image via the standard baseline/append pattern. Consumers with existing `prom/alertmanager` state (uid 65534) see mutual readability.
   - **SSL_CERT_FILE re-declaration** — mandatory. Without it, every Telegram / Mattermost / email webhook fails.
   - **SIGHUP config reload** — alertmanager reloads config via SIGHUP; must be preserved through the direct ENTRYPOINT.
   - **amtool via docker exec** — scratch has no shell; amtool runs directly via `docker exec --interactive=false <container> /usr/bin/amtool check-config ...`.
   - **Clustering (`--cluster.*` flags)** — out of scope for the image shape; consumer-concern command-line flags.
   - **No embedded default config** — alertmanager will refuse to start without a routed receiver. The shipped default `/etc/alertmanager/alertmanager.yml` must contain a no-op `null` receiver so `docker run <image>` succeeds for the smoke suite; production consumers mount their own.

7. **Out of scope**:
   - Baking real notification credentials (Telegram tokens, etc.). Consumer secret material.
   - Clustering / HA deployment (gossip across replicas). Consumer concern.
   - Running alertmanager + prometheus in the same container. Hard split.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.alertmanager-routes-alerts` — image runs alertmanager server, responds to `/-/healthy`, serves `/api/v2/alerts`, initiates outbound HTTPS for webhook delivery.
   - EXT `image.ssl-cert-env` — another scratch derivative re-declaring SSL_CERT_FILE.
   - EXT `build.two-stage-scratch`, `build.scratch-baseline`.

## Gherkin acceptance

```
Scenario: alertmanager-scratch-trixie:0.28 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists prometheus-alertmanager 0.28.1
   And the grype attestation is attached with zero Debian-source matches

Scenario: /-/healthy responds 200 after boot
  Given a running forge-local/alertmanager-scratch-trixie:0.28 with minimal config
  When `curl http://localhost:9093/-/healthy` runs after a startup grace period
  Then the response is HTTP 200

Scenario: /-/ready responds 200 after warmup
  Given a running alertmanager
  When `curl http://localhost:9093/-/ready` runs
  Then the response is HTTP 200

Scenario: amtool validates config via docker exec
  Given a running alertmanager
  When `docker exec <container> /usr/bin/amtool check-config /etc/alertmanager/alertmanager.yml` runs
  Then the exit code is 0
   And stdout contains "SUCCESS"

Scenario: Outbound HTTPS webhook delivery (proves CA bundle resolved)
  Given a running alertmanager with a webhook_config pointing at a public HTTPS echo endpoint
  When a test alert is POSTed to /api/v2/alerts
  Then the container logs show successful webhook delivery
   And no `x509: certificate signed by unknown authority` error appears

Scenario: SIGHUP reloads config without restarting the container
  Given a running alertmanager
  When the host sends SIGHUP to PID 1
  Then the container stays running
   And `amtool` validates the (potentially updated) config

Scenario: Image has no shell
  Given the built image
  When common shell paths are probed via docker run --entrypoint
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh all fail to exec

Scenario: Image runs as nonroot (uid 65534)
  Given the built image
  When `docker inspect --format {{.Config.User}}` is read
  Then it is `65534:65534`

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 100 MB
```

## References

- Plan: `docs/plan/FG-036-alertmanager-scratch-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_036_alertmanager-scratch-trixie.sh`
- Capabilities: `docs/CAPABILITIES.md` (NEW `image.alertmanager-routes-alerts`)
- Upstream: Debian trixie `prometheus-alertmanager` 0.28.1+ds-1
- Reference pattern: FG-035 (prometheus — same TLS + SIGHUP + amtool/promtool design)
