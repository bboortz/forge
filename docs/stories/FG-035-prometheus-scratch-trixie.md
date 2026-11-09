---
id: FG-035
slug: prometheus-scratch-trixie
status: draft
owner: bboortz
created: 2026-11-08
---

# FG-035 — prometheus-scratch-trixie

New Forge image: `ghcr.io/bboortz/prometheus-scratch-trixie:2.53` — Prometheus server 2.53.3 (from Debian trixie's `prometheus` apt package), `FROM scratch` runtime via `scratch-base-trixie`. Enables homelab's central metrics server with a signed/scanned/attested Forge base replacing `prom/prometheus:latest`.

Unlike node_exporter, prometheus does initiate outbound TLS — for `remote_write` targets (Grafana Cloud, long-term storage) and for alertmanager HTTP delivery when consumers configure HTTPS. The baseline already ships `/etc/ssl/certs/ca-certificates.crt`, so the overlay doesn't need to add CA data — but the Dockerfile must re-declare `ENV SSL_CERT_FILE=…` per the FG-009 "ENV doesn't propagate" lesson.

## 9 canonical answers

1. **Who** — homelab operator running a central prometheus instance scraping every host's node_exporter + ipmi_exporter + service-specific exporters, and forwarding alerts to alertmanager. Secondary: any Forge consumer wanting a signed Prometheus server.

2. **When** — fires at every prometheus boot (compose up); at every scrape cycle; at every `remote_write` POST; at every `/-/healthy` probe. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/prometheus-scratch-trixie:2.53` publishes daily with cosign + SBOM + scan attestations.
   - `docker run -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml -p 9090:9090 <image>` boots a running instance.
   - `curl http://localhost:9090/-/healthy` returns `Prometheus Server is Healthy.` with HTTP 200.
   - `curl http://localhost:9090/-/ready` returns `Prometheus Server is Ready.` once scrape loop initializes.
   - Outbound HTTPS from the container (e.g. `remote_write` to any public HTTPS endpoint) succeeds — TLS handshake works via the baseline CA bundle.
   - Image size ≤ 300 MB (Debian ships ~250 MB installed: binary + console_libraries + console_templates).
   - grype reports zero Debian-source matches (scratch runtime, no dpkg DB).
   - Homelab compose line swap: `image: prom/prometheus:latest` → `image: ghcr.io/bboortz/prometheus-scratch-trixie:2.53`. Volume mounts (`/etc/prometheus/`, `/prometheus/`) unchanged.

4. **Urgency** — quality-of-life + supply-chain. Homelab currently pulls `prom/prometheus:latest`; moving to the Forge build gives daily rebuilds + Debian CVE tracking + the full attestation triple.

5. **Happy path**:
   1. Forge daily cron publishes `:2.53` + `:latest`.
   2. Homelab compose updates `image:` reference.
   3. prometheus boots against its existing `prometheus.yml` + TSDB volume.
   4. Scraping continues, alerting rules fire into alertmanager, consumer dashboards work unchanged.

6. **Edge cases / failure modes**:
   - **TSDB volume ownership** — Debian's package creates the `prometheus` user with some uid. We pin the service user to **65534 (nobody)** in /etc/passwd via the baseline — safe default that maps to "nonroot with no special permissions." Consumers with existing TSDB data from `prom/prometheus` (uid 65534 upstream) remain mutually readable. **Document this uid pin** in the plan since mismatched uids on persistent volumes would break startup.
   - **`console_libraries` + `console_templates`** — prometheus looks at `/usr/share/prometheus/console_libraries/` by default; must be shipped in the overlay. Without them, the `/consoles` UI path returns errors (non-fatal; headless operators don't care).
   - **No shell for `docker exec`** — standard scratch trade-off. `promtool` ships in the Debian package; we also include it in the overlay so consumers can `docker exec <container> /usr/bin/promtool check config /etc/prometheus/prometheus.yml` for config validation (binary form, no shell needed).
   - **SIGHUP config reload** — prometheus honors SIGHUP for config + rules reload. Must be preserved through the scratch runtime (ENTRYPOINT direct, not wrapped).
   - **`SSL_CERT_FILE` ENV re-declaration** — baseline's ENV doesn't propagate; must re-declare per FG-009.

7. **Out of scope**:
   - Baking a default `prometheus.yml` config. Consumers always mount their own.
   - Pushgateway, blackbox_exporter, or any other Prometheus-ecosystem image — separate FG stories if ever needed.
   - Clustering / HA (promxy, Thanos). Consumer concern.
   - Changing storage backend. TSDB on local volume stays.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.prometheus-serves-metrics` — image runs prometheus server, responds to `/-/healthy`, serves `/metrics` + `/api/v1/*`, initiates outbound HTTPS for remote_write.
   - EXT `image.ssl-cert-env` — another scratch derivative re-declaring SSL_CERT_FILE.
   - EXT `build.two-stage-scratch`, `build.scratch-baseline`, `test.sidecar-init` (for config-testing flows).

## Gherkin acceptance

```
Scenario: prometheus-scratch-trixie:2.53 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists prometheus 2.53.3
   And the grype attestation is attached with zero Debian-source matches

Scenario: /-/healthy responds 200 after boot
  Given a running forge-local/prometheus-scratch-trixie:2.53 with minimal config
  When `curl http://localhost:9090/-/healthy` runs after a startup grace period
  Then the response is HTTP 200
   And the body is `Prometheus Server is Healthy.\n`

Scenario: /-/ready responds 200 after warmup
  Given a running prometheus that has completed initial scrape setup
  When `curl http://localhost:9090/-/ready` runs
  Then the response is HTTP 200
   And the body is `Prometheus Server is Ready.\n`

Scenario: promtool validates config via docker exec
  Given a running prometheus
  When `docker exec <container> /usr/bin/promtool check config /etc/prometheus/prometheus.yml` runs
  Then the exit code is 0
   And stdout contains "SUCCESS"

Scenario: SIGHUP reloads config without restarting the container
  Given a running prometheus
  When the host writes an updated prometheus.yml to the mounted config
   And sends SIGHUP to the container's PID 1
  Then the container stays running
   And `promtool` validates the new config

Scenario: Outbound HTTPS works (remote_write prerequisites)
  Given a running prometheus
  When the container attempts a TLS handshake to a public HTTPS endpoint
  Then it succeeds (CA bundle resolved; proves ENV SSL_CERT_FILE re-declared)

Scenario: Image has no shell
  Given the built image
  When common shell paths are probed via docker run --entrypoint
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh all fail to exec

Scenario: Image runs as nonroot (uid 65534, nobody)
  Given the built image
  When `docker inspect --format {{.Config.User}}` is read
  Then it is `65534:65534`

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 300 MB
```

## References

- Plan: `docs/plan/FG-035-prometheus-scratch-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_035_prometheus-scratch-trixie.sh`
- Capabilities: `docs/CAPABILITIES.md` (NEW `image.prometheus-serves-metrics`)
- Upstream: Debian trixie `prometheus` 2.53.3+ds1-2
- Reference pattern: FG-006 (nginx-scratch — HTTP server), FG-033 (SSL_CERT_FILE re-declaration)
