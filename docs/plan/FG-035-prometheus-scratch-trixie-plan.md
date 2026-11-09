# FG-035 — Plan: prometheus-scratch-trixie

**Story**: [`docs/stories/FG-035-prometheus-scratch-trixie.md`](../stories/FG-035-prometheus-scratch-trixie.md)
**Status**: draft
**Branch**: `feat/FG-035-prometheus-scratch-trixie`

## Design delta

### `images/prometheus-scratch-trixie/` (new)

- `image.yaml`: tag `"2.53"`, platforms `[linux/amd64]`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage.
  - Builder: `FROM forge-builder-trixie` → `apt-get install prometheus promtool` (promtool is in same `prometheus` package) → syft SBOM → stage overlay:
    - `/usr/bin/prometheus` + `/usr/bin/promtool`
    - `/usr/share/prometheus/console_libraries/` + `/usr/share/prometheus/consoles/`
    - ldd closure of the prometheus binary (dynamic Go on Debian — needs libc + libpthread + libdl at minimum)
    - writable `/prometheus/` + `/etc/prometheus/` (pre-created, owned 65534:65534)
    - append `nobody:x:65534:65534:prometheus:/prometheus:/sbin/nologin` to baseline's /etc/passwd (if not already — baseline ships nobody at 65534; append pattern preserves it)
  - Runtime: `FROM scratch` + `COPY --from=scratch_base / /` + `COPY --from=builder /out /`. `ENTRYPOINT ["/usr/bin/prometheus"]`, `CMD ["--config.file=/etc/prometheus/prometheus.yml", "--storage.tsdb.path=/prometheus", "--web.console.libraries=/usr/share/prometheus/console_libraries", "--web.console.templates=/usr/share/prometheus/consoles", "--web.listen-address=:9090"]`, `USER 65534:65534`, `WORKDIR /prometheus`, `EXPOSE 9090`.
  - `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`, `ENV SSL_CERT_DIR=/etc/ssl/certs` (FG-009 re-declaration).
- `PROMISES.yaml` (new): `runtime.prometheus-binary`, `runtime.healthy-endpoint`, `runtime.ready-endpoint`, `runtime.promtool-available`, `runtime.sighup-reload`, `runtime.outbound-tls`, `absence.shell`, `absence.os-cves`, `shape.size-budget` (≤ 300 MB). `version: "0.1"`.
- `EXPECTATIONS.yaml`: FG-010 contract on `scratch-base-trixie >= 0.2` (ld-linux, glibc, TLS stack, CA bundle, /etc/passwd+group, /tmp 1777).

### Smoke tests

- `smoke_binary_runs.sh` — `prometheus --version` prints `prometheus, version 2.53.3`.
- `smoke_healthy_endpoint.sh` — `scripts/smoke-server.sh --image <IMAGE> --port 9090 --ready 'curl -sf http://localhost:__HOST_PORT__/-/healthy' --test 'curl -sf http://localhost:__HOST_PORT__/-/healthy | grep -q "Healthy"'`.
- `smoke_ready_endpoint.sh` — same pattern against `/-/ready`.
- `smoke_promtool_validates.sh` — boot prometheus, `docker exec <CID> /usr/bin/promtool check config /etc/prometheus/prometheus.yml` exits 0.
- `smoke_sighup_reload.sh` — boot, `docker kill -s SIGHUP <CID>`, container still running + `/-/healthy` still 200.
- `smoke_outbound_tls.sh` — `docker exec <CID> /usr/bin/promtool query <some>` is tricky; simpler: inspect that `/etc/ssl/certs/ca-certificates.crt` exists in image (content check via docker save) — proves the CA path is present. Real TLS handshake exercised by mounting a `prometheus.yml` with `remote_write.url: https://httpbin.org/...` and checking boot logs don't carry `x509` errors.
- `smoke_no_shell.sh` — standard.
- `smoke_user_nonroot.sh` — `docker inspect` user == `65534:65534`.
- `smoke_size.sh` — ≤ 300 MB.
- `smoke_zero_os_cves.sh` — grype dpkg-source count == 0.

### Default `prometheus.yml` config shipped at `/etc/prometheus/prometheus.yml`

Minimal (operator mounts their own in prod):
```yaml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
```

This lets `docker run <image>` succeed with zero config — useful for the smoke test harness. Prod consumers mount their own at the same path.

### Acceptance test

`tests/acceptance/test_FG_035_prometheus-scratch-trixie.sh` — 4 sections (files, build, smoke suite, image.yaml invariants).

### No workflow changes

`build.yml` discover job picks it up automatically.

## Alternatives rejected

- **Pull binary from upstream `prom/prometheus` Docker Hub** — bypasses Debian's security tracking. Same reasoning as FG-034.
- **Skip console_libraries/templates** — breaks the `/consoles` UI path (not a hot path; some operators use it). Shipping is ~2 MB; acceptable.
- **Base on `-slim` (Debian runtime)** — bigger surface area; prometheus doesn't need a shell at runtime. promtool exec via docker exec covers config validation.
- **Pin a specific uid for the service user other than 65534 (nobody)** — upstream `prom/prometheus` uses 65534; mutual readability on TSDB volumes is the right default.

## Breaking changes

- **TSDB volume ownership**: pre-FG-035 `prom/prometheus` uses uid 65534. FG-035 also uses 65534. Migration is clean (same uid → volume readable as-is).
- **Default command-line flags**: FG-035 bakes the standard Debian defaults in `CMD`. Consumers who need custom flags override `command:` in their compose. Same ergonomic as upstream.
- No change to the public verify command, GHCR layout, or attestation format.

## Merge plan

- All blocking gates pass.
- FG-035 acceptance green.
- `scan-baseline.json` committed.
- Image size recorded.

## Rollout plan

1. Land on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Daily cron publishes.
4. Homelab PR swaps `image:` reference on the central prometheus service.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_035_...sh` § 1 | ⏳ |
| Scenario: /-/healthy responds 200 | § 3 + smoke_healthy_endpoint.sh | ⏳ |
| Scenario: /-/ready responds 200 | § 3 + smoke_ready_endpoint.sh | ⏳ |
| Scenario: promtool validates via docker exec | § 3 + smoke_promtool_validates.sh | ⏳ |
| Scenario: SIGHUP config reload | § 3 + smoke_sighup_reload.sh | ⏳ |
| Scenario: outbound HTTPS works (CA path) | § 3 + smoke_outbound_tls.sh | ⏳ |
| Scenario: no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: nonroot uid 65534 | § 3 + smoke_user_nonroot.sh | ⏳ |
| Scenario: size ≤ 300 MB | § 3 + smoke_size.sh | ⏳ |
| NEW CAP `image.prometheus-serves-metrics` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
