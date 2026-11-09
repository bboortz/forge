---
id: FG-034
slug: node-exporter-scratch-trixie
status: draft
owner: bboortz
created: 2026-11-08
---

# FG-034 — node-exporter-scratch-trixie

New Forge image: `ghcr.io/bboortz/node-exporter-scratch-trixie:1.9` — Prometheus node_exporter 1.9.0 (from Debian trixie's `prometheus-node-exporter` apt package), `FROM scratch` runtime via `scratch-base-trixie`. Enables homelab's per-host metrics collection with a signed/scanned/attested Forge base replacing `prom/node-exporter:latest` from Docker Hub.

node_exporter scrapes `/proc`, `/sys`, and some `/etc/*-release` paths — it does **not** initiate outbound TLS, so no CA bundle work is needed beyond what the baseline already ships. The upstream is a Go binary; Debian builds it dynamically against glibc, so we need libc (baseline supplies it). No shell required — node_exporter is invoked directly.

## 9 canonical answers

1. **Who** — homelab operator (me) running one node_exporter container per host for prometheus scraping. Secondary: any Forge consumer wanting a signed Prometheus node_exporter with zero OS-package attack surface.

2. **When** — fires at every host boot (compose brings up the exporter); at every prometheus scrape cycle; at every `curl http://host:9100/metrics`. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/node-exporter-scratch-trixie:1.9` publishes daily with cosign + SBOM + scan attestations.
   - `docker run --rm -p 9100:9100 <image>` → `curl http://localhost:9100/metrics` returns Prometheus text format (lines like `node_cpu_seconds_total{...}`).
   - Image size ≤ 30 MB (binary is ~22 MB; baseline adds ~13 MB; expect ~30 MB final).
   - grype reports zero Debian-source matches (scratch runtime, no dpkg DB).
   - Homelab compose line swap: `image: prom/node-exporter:latest` → `image: ghcr.io/bboortz/node-exporter-scratch-trixie:1.9`. Volumes + ports unchanged.

4. **Urgency** — quality-of-life. Current homelab uses `prom/node-exporter:latest` (upstream image with its own cadence). Supply-chain-controlled Forge build gives deterministic daily rebuilds with Debian CVE tracking.

5. **Happy path**:
   1. Forge daily cron publishes `:1.9` + `:latest`.
   2. Homelab compose updates `image:` reference.
   3. `docker compose up -d` — the new container drops in; prometheus continues scraping without config change (same port :9100, same `/metrics` path).

6. **Edge cases / failure modes**:
   - **Host /proc + /sys mounts** — node_exporter typically runs with `-v /proc:/host/proc:ro -v /sys:/host/sys:ro` + `--path.procfs=/host/proc` etc. The scratch image doesn't dictate those mounts (consumer concern); but the smoke test must boot the image without them and still verify `/metrics` responds (node_exporter exposes a baseline of self-metrics from in-container /proc).
   - **No shell for `docker exec` debugging** — standard scratch trade-off. Operators use `docker logs`.
   - **Service user** — upstream Debian package expects a `prometheus` user; our image runs as the baseline nonroot (uid 65532) since node_exporter doesn't need elevated privileges to read /proc.
   - **Binary path** — Debian names the binary `/usr/bin/prometheus-node-exporter`, not `/bin/node_exporter`. Document the Forge path in README so consumers know what to override if they bake on top.

7. **Out of scope**:
   - Textfile collector scripts (`prometheus-node-exporter-collectors` apt package) — consumers who need these bake a derived image.
   - Multi-arch (arm64) — stays amd64-only (every current Forge image).
   - Changing the `--path.procfs` / `--path.sysfs` defaults — those are command-line flags the operator sets.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.node-exporter-serves-metrics` — image runs node_exporter, responds to `GET /metrics` with Prometheus text format, no TLS required.
   - EXT `build.two-stage-scratch` — another instance of the pattern.
   - EXT `build.scratch-baseline` — another derivative of `scratch-base-trixie`.

## Gherkin acceptance

```
Scenario: node-exporter-scratch-trixie:1.9 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists prometheus-node-exporter 1.9.0
   And the grype attestation is attached with zero Debian-source matches

Scenario: /metrics endpoint responds with Prometheus text format
  Given a running forge-local/node-exporter-scratch-trixie:1.9 on port 9100
  When `curl http://localhost:9100/metrics` runs
  Then the response is HTTP 200
   And the body contains `# TYPE node_` lines (Prometheus format)
   And the body contains at least one metric name matching `node_.*_seconds_total`

Scenario: Image has no shell
  Given the built image
  When common shell paths are probed via docker run --entrypoint
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh all fail to exec

Scenario: Image runs as nonroot (uid 65532)
  Given the built image
  When `docker inspect --format {{.Config.User}}` is read
  Then it is `65532:65532`

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 30 MB

Scenario: Homelab compose swap works
  Given homelab's docker-compose referencing prom/node-exporter:latest
  When the `image:` line is swapped to ghcr.io/bboortz/node-exporter-scratch-trixie:1.9
  Then `docker compose up -d` boots the container successfully
   And prometheus continues to scrape :9100/metrics without config change
```

## References

- Plan: `docs/plan/FG-034-node-exporter-scratch-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_034_node-exporter-scratch-trixie.sh`
- Capabilities: see `docs/CAPABILITIES.md` (NEW `image.node-exporter-serves-metrics`)
- Upstream: Debian trixie `prometheus-node-exporter` 1.9.0-1+b4
- Reference pattern: FG-027 (redis-scratch), FG-028 (mosquitto-scratch)
