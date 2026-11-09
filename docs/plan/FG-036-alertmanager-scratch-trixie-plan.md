# FG-036 — Plan: alertmanager-scratch-trixie

**Story**: [`docs/stories/FG-036-alertmanager-scratch-trixie.md`](../stories/FG-036-alertmanager-scratch-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-036-alertmanager-scratch-trixie`

## Design delta

### `images/alertmanager-scratch-trixie/` (new)

- `image.yaml`: tag `"0.28"`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage. Builder apt-installs `prometheus-alertmanager` (which brings `amtool` in the same package), syft SBOM, stages binary + ldd closure + `/etc/alertmanager/` + `/alertmanager/` (owned 65534). Runtime overlay + ENV SSL_CERT_FILE re-declaration + ENTRYPOINT `/usr/bin/prometheus-alertmanager`, CMD with the standard flags (`--config.file=/etc/alertmanager/alertmanager.yml --storage.path=/alertmanager --web.listen-address=:9093`), USER 65534, EXPOSE 9093.
- `PROMISES.yaml`: promises for `runtime.alertmanager-binary`, `runtime.healthy-endpoint`, `runtime.ready-endpoint`, `runtime.amtool-available`, `runtime.sighup-reload`, `runtime.outbound-tls`, `absence.shell`, `absence.os-cves`, `shape.size-budget` (≤ 100 MB). `version: "0.1"`.
- `EXPECTATIONS.yaml`: scratch-base-trixie ≥ 0.2 (ld-linux, glibc, TLS stack, CA bundle, /etc/passwd+group nobody, /tmp 1777).
- `alertmanager.yml` (shipped default — null receiver so container boots):
  ```yaml
  route:
    receiver: default
  receivers:
    - name: default
  ```

### Smoke tests

- `smoke_binary_runs.sh` — `prometheus-alertmanager --version` prints `alertmanager, version 0.28.1`.
- `smoke_healthy_endpoint.sh` — uses `scripts/smoke-server.sh`.
- `smoke_ready_endpoint.sh` — same against `/-/ready`.
- `smoke_amtool_validates.sh` — `docker exec <CID> /usr/bin/amtool check-config …` exits 0.
- `smoke_sighup_reload.sh` — SIGHUP, assert container stays up.
- `smoke_outbound_tls.sh` — minimal check: mount a config with a `url: https://httpbin.org/post` webhook, POST a test alert, inspect logs for success message and absence of `x509` error. Fallback (if public network unavailable in CI): verify `/etc/ssl/certs/ca-certificates.crt` + `ENV SSL_CERT_FILE` set via image inspect.
- `smoke_no_shell.sh`, `smoke_user_nonroot.sh`, `smoke_size.sh`, `smoke_zero_os_cves.sh` — standard.

### Acceptance test

`tests/acceptance/test_FG_036_alertmanager-scratch-trixie.sh` — 4 sections.

## Alternatives rejected

- **Pull binary from upstream `prom/alertmanager`** — bypasses Debian security tracking.
- **Base on `-slim`** — bigger surface area; no shell needed at runtime.
- **Skip the default alertmanager.yml** — image would fail to boot without an operator-provided config; smoke test harness needs it.
- **Clustering flags baked into CMD** — operator-managed; consumers override `command:`.

## Breaking changes

- **Persistent storage uid**: same 65534 as upstream `prom/alertmanager`. Mutual readability on migration.
- No change to public contracts.

## Merge plan

- Blocking gates pass. Acceptance green. scan-baseline committed. Image size recorded.

## Rollout plan

1. Land on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Daily cron publishes.
4. Homelab PR swaps `image:`.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_036_...sh` § 1 | ⏳ |
| Scenario: /-/healthy | § 3 + smoke_healthy_endpoint.sh | ⏳ |
| Scenario: /-/ready | § 3 + smoke_ready_endpoint.sh | ⏳ |
| Scenario: amtool via docker exec | § 3 + smoke_amtool_validates.sh | ⏳ |
| Scenario: SIGHUP reload | § 3 + smoke_sighup_reload.sh | ⏳ |
| Scenario: outbound HTTPS | § 3 + smoke_outbound_tls.sh | ⏳ |
| Scenario: no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: nonroot uid 65534 | § 3 + smoke_user_nonroot.sh | ⏳ |
| Scenario: size ≤ 100 MB | § 3 + smoke_size.sh | ⏳ |
| NEW CAP `image.alertmanager-routes-alerts` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
