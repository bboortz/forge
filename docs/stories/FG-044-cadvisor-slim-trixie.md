---
id: FG-044
slug: cadvisor-slim-trixie
status: draft
owner: bboortz
created: 2026-11-09
---

# FG-044 — cadvisor-slim-trixie (built from Go source)

Homelab monitoring stack already runs ipmi-exporter + node-exporter + prometheus + alertmanager from Forge. The one missing exporter is **cAdvisor** (container-level resource + perf metrics). Upstream ships only an Alpine/musl image; Forge is glibc-world. This story ships `cadvisor-slim-trixie:0.60.6` built from Go source on `golang:1.27-trixie` → `debian:trixie-slim` runtime, keeping the Debian-ecosystem thesis intact.

Target deployment: homelab (every host with a Docker daemon gets a cadvisor sidecar — same pattern as node-exporter).

## 9 canonical answers

1. **Who** — homelab operator (me) first, deploying as a per-host container-metrics sidecar alongside the existing scratch exporter fleet. Secondary: any Forge consumer wanting a cadvisor that aligns with their Debian supply chain (not Alpine).

2. **When** — fires at every `docker compose up` on a homelab host with Docker + cgroup access. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/cadvisor-slim-trixie:0.60.6` publishes daily with cosign + SBOM + scan attestations.
   - `docker run --rm -d -p 8080:8080 -v /sys:/sys:ro -v /:/rootfs:ro -v /var/lib/docker/:/var/lib/docker:ro -v /var/run:/var/run:ro --name cadvisor <image>` boots on any homelab host.
   - `curl -sf http://localhost:8080/healthz` returns `ok`.
   - `curl -sf http://localhost:8080/metrics | grep '^cadvisor_version_info'` shows `cadvisorVersion="v0.60.6"`.
   - `curl -sf http://localhost:8080/metrics | grep '^container_cpu_usage_seconds_total'` returns at least one series per running container.
   - Image size ≤ 150 MB.
   - Build from source on `golang:1.27-trixie`, static Go binary (`CGO_ENABLED=0 -tags netgo`), zero dynamic lib deps on the binary itself.
   - Homelab prometheus server scrapes the new `:8080` target without further config beyond adding a `scrape_config`.

4. **Urgency** — quality-of-life + supply-chain. Homelab lacks container-level metrics today (only host metrics via node-exporter). Not emergency; ship when touching the stack.

5. **Happy path**:
   1. Forge daily cron publishes `:0.60.6` + `:latest`.
   2. Homelab compose per host adds a `cadvisor` service pointing at `ghcr.io/bboortz/cadvisor-slim-trixie:latest`.
   3. `docker compose up -d` — container boots, reads cgroups from `/sys`, exposes `:8080`.
   4. Prometheus `scrape_configs` adds the new targets; dashboards start populating per-container CPU/RAM/network.

6. **Edge cases / failure modes**:
   - **No /sys mount** — cadvisor still serves `/healthz` and `/metrics` but container-level metrics are empty. Smoke tests the `/sys:/sys:ro`-mounted path; the no-sys path is the operator's config problem.
   - **cgroup v1 vs v2** — cadvisor supports both; homelab hosts are cgroup v2 (Debian trixie default).
   - **No Docker socket access** — cadvisor can still enumerate containers via `/var/lib/docker:ro` metadata; `docker.sock` is optional.
   - **Static binary + libc ABI** — `CGO_ENABLED=0` means cadvisor has zero dyn deps. A future flip to CGO (e.g. to re-enable perf_event collection via libpfm) would silently add a dep; `smoke_static_binary.sh` guards this.
   - **Upstream deprecates `-port` flag** — currently supported; if upstream renames, CMD line needs updating. Tracked implicitly via the daily rebuild + smoke.

7. **Out of scope**:
   - **libpfm / perf events**. Homelab doesn't need microarchitecture metrics. Keeping CGO off produces a simpler, smaller, more portable binary.
   - **Scratch runtime**. Deferred — would need to ship a few glibc libs OR rebuild with a tiny-ca-certs-only runtime; marginal win over the 100 MB slim baseline. Can be a FG-NNN follow-up (same pattern as FG-037 → FG-043).
   - **Multi-arch**. amd64-only matches every other Forge image.
   - **Running as non-root**. Upstream explicitly requires either root + mounts OR seccomp profile tweaks; homelab turnkey story keeps root.
   - **Per-host cadvisor config files**. Default flags suffice for homelab. Operators who need custom collectors / scoping pass `-enable_metrics=…` at `docker run` time.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.cadvisor-serves-metrics` — container-metrics endpoint on :8080 with cadvisor_version_info + container_* series when /sys is mounted. Analog of `image.ipmi-exporter-serves-metrics`.
   - NEW `build.from-go-source` — pattern for building Go-source images (golang:X-trixie builder stage → debian:trixie-slim runtime → static binary → SBOM via syft against source tree). Future Go-source consumers (jaeger, nomad, consul if we ever ship them) will reference this CAP. If the Go-source image count reaches ≥2, consider extracting `forge-builder-go-trixie` (tracked in IDEAS).

## Gherkin acceptance

```
Scenario: cadvisor-slim-trixie:0.60.6 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists cadvisor's Go module graph + debian-slim dpkg list
   And the grype scan is attached (nonzero CRITICAL CVEs allowed via scan-baseline.json — slim contract)

Scenario: cadvisor binary reports its version
  Given the built image
  When `docker run <image> -version` runs
  Then stdout contains `cAdvisor version v0.60.6`

Scenario: cadvisor binary is statically linked
  Given the built image
  When `ldd /usr/bin/cadvisor` is run via docker
  Then the output contains "not a dynamic executable" OR "statically linked"

Scenario: /healthz responds with "ok" within 20s of boot
  Given a running forge-local/cadvisor-slim-trixie:0.60.6 with /sys:/sys:ro mounted
  When `curl http://localhost:8080/healthz` runs
  Then the response is HTTP 200
   And the body is "ok"

Scenario: /metrics exposes cadvisor_version_info + container_ series
  Given a running forge-local/cadvisor-slim-trixie:0.60.6 with /sys mounted
  When `curl http://localhost:8080/metrics` runs
  Then the response is HTTP 200
   And the body contains `# TYPE cadvisor_`
   And the body contains `cadvisor_version_info`

Scenario: Image has shell (slim contract)
  Given the built image
  When `docker run --entrypoint=/bin/sh <image> -c 'echo ok'` runs
  Then stdout is "ok"
   And rc is 0

Scenario: /hc baked HEALTHCHECK polls /healthz
  Given the built image
  When `docker inspect --format {{.Config.Healthcheck.Test}}` is read
  Then it contains "/hc" and "/healthz" and "127.0.0.1:8080"
   And a running container becomes `healthy` within 15s (with /sys mount)

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 150 MB

Scenario: Homelab adoption (operator-side, documented)
  Given a homelab Docker host with cgroups + Docker daemon
  When the operator adds a `cadvisor` service to compose pointing at `ghcr.io/bboortz/cadvisor-slim-trixie:latest`
   And `docker compose up -d cadvisor` succeeds
   And prometheus scrapes `:8080/metrics`
  Then dashboards populate with per-container CPU/RAM/network metrics within one scrape interval
```

## References

- Plan: `docs/plan/FG-044-cadvisor-slim-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_044_cadvisor-slim-trixie.sh`
- Upstream: `github.com/google/cadvisor` v0.60.6 (released 2026-09-18)
- Related: FG-037 (ipmi-exporter-slim-trixie — same slim pattern), FG-025 (forge-builder-trixie — centralizes apt-upgrade for scratch builders; cadvisor doesn't use it because the Go builder stage replaces that role for Go-source images)
- Future: `forge-builder-go-trixie` extraction (IDEAS.md) — promote to FG-NNN when the 2nd Go-source consumer lands
