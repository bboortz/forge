# Capabilities matrix

The source of truth for what Forge can do. Every entry has bidirectional links to the acceptance test(s) that exercise it; `make verify-traceability` enforces that both directions are present.

Format per entry:

```
### <cap.id>

One-line description.

- **Delivered by**: FG-NNN
- **Covered by**: `tests/acceptance/test_FG_NNN_<slug>.sh`
```

CAP id convention: `<domain>.<verb-or-shape>`. Domains in current use: `build`, `scan`, `sbom`, `sign`, `verify`, `publish`, `pins`.

---

### build.pr-ci

On push to `dev` or PR targeting `dev`, build the affected image(s) and run grype against each. Does not push to GHCR. Lives in `.github/workflows/ci.yml` as the full-check job.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### build.daily-publish

Daily 03:00 UTC cron (`workflow_dispatch` also available) builds every image with `--pull`, attaches attestations, signs, and pushes. FG-057 adds a `workflow_dispatch.inputs.images` filter so operators can scope a manual publish to one image / comma list / glob; scheduled cron ignores the input and always publishes everything.

- **Delivered by**: FG-001
- **Extended by**: FG-057 (workflow_dispatch image filter)
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`, `tests/acceptance/test_FG_057_build-image-filter.sh`

### sbom.cyclonedx-attest

syft produces a CycloneDX JSON SBOM for every built image. The SBOM is attached to the digest as an OCI attestation.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### scan.grype-attest

grype scans every built image. The JSON result is attached to the digest as an OCI attestation.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### sign.cosign-keyless-oidc

In GitHub Actions, cosign signs the digest keylessly, using the workflow's OIDC token. FG-041 bumped the pinned cosign binary to v2.6.5 (patches GHSA-fx35-mq7g-6g98, a HIGH verification-bypass CVE).

- **Delivered by**: FG-001
- **Extended by**: FG-041 (cosign pin v2.4.3 → v2.6.5)
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`, `tests/acceptance/test_FG_041_cosign-v2.6.5-pin.sh`

### sign.cosign-local-dev

For out-of-CI development, `make sign-local` uses a local cosign key pair under `.cosign/` (gitignored). Locally signed digests are never pushed to `ghcr.io/bboortz/`.

- **Delivered by**: FG-001
- **Extended by**: FG-041 (cosign pin v2.4.3 → v2.6.5; `--tlog-upload=false` behavior preserved in v2.6.x)
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`, `tests/acceptance/test_FG_041_cosign-v2.6.5-pin.sh`

### ci.cosign-pin-drift-gate

`tests/acceptance/test_FG_041_cosign-v2.6.5-pin.sh` enforces three invariants on the cosign pin: (1) every workflow + `Makefile` + `scripts/` reference to a cosign version cites the same version (`v2.6.5`); (2) the review date in `memory/supply-chain.md` is strictly in the future; (3) **fails the build 7 days before the review date** so the operator ships a renew/upgrade/migrate decision before silent drift. Testable via `FG_041_TODAY=YYYY-MM-DD` env override. Replaces the "operator remembers to re-check the cosign pin" pattern with a CI gate.

- **Delivered by**: FG-041
- **Covered by**: `tests/acceptance/test_FG_041_cosign-v2.6.5-pin.sh`

### verify.consumer-cmd

`cosign verify --certificate-identity .../build.yml --certificate-oidc-issuer https://token.actions.githubusercontent.com <image>` succeeds against any Forge-published digest from any workstation with cosign installed.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### publish.ghcr-public-pull

`docker pull ghcr.io/bboortz/<image>:<tag>` succeeds without authentication.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### test.image-smoke-suite

Per-image contract tests live co-located with the recipe under `images/<name>/tests/*.sh`. Each image maintains its own guarantees; deleting the image removes its tests cleanly.

- **Delivered by**: FG-002
- **Covered by**: `tests/acceptance/test_FG_002_python-image-smoke-suite.sh`

### test.makefile-glob

`make test-images` (optionally scoped by `IMAGE_NAME=<name>`) discovers and runs every `images/*/tests/*.sh` against the just-built local image. Aggregated into `make check`.

- **Delivered by**: FG-002
- **Covered by**: `tests/acceptance/test_FG_002_python-image-smoke-suite.sh`

### test.size-budget

Every image asserts its final size is at most **upstream base × 1.1**, where "upstream base" is the `FROM` reference used in the Dockerfile. 10% headroom accommodates `apt upgrade` deltas. Scratch variants add an additional hard byte-ceiling (60 MB for python-scratch-trixie).

- **Delivered by**: FG-002 (base × 1.1)
- **Extended by**: FG-003 (scratch hard ceiling)
- **Covered by**: `images/python-slim-trixie/tests/smoke_size.sh`, `images/python-scratch-trixie/tests/smoke_size.sh`

### build.two-stage-scratch

Two-stage Dockerfile pattern: builder stage on a conventional Debian base, runtime stage `FROM scratch` with explicit COPY lines enumerating the ldd closure + CA bundle + zoneinfo + nss.

- **Delivered by**: FG-003
- **Covered by**: `tests/acceptance/test_FG_003_python-scratch-runtime.sh`

### image.no-shell

Scratch-runtime variants contain no `/bin/sh` or other shells. Attempting `docker run --rm --entrypoint=/bin/sh <image>` fails.

- **Delivered by**: FG-003
- **Covered by**: `images/python-scratch-trixie/tests/smoke_scratch_no_shell.sh`

### image.zero-os-cves

grype run against a scratch-runtime image reports zero matches whose source is a Debian package. Every surviving finding is a PyPI dep the consumer installed — no OS-package noise.

- **Delivered by**: FG-003
- **Covered by**: `images/python-scratch-trixie/tests/smoke_scratch_zero_os_cves.sh`

### build.central-script

Single `scripts/build-image.sh <image-dir>` drives every image build. Reads `images/<dir>/image.yaml` for the publishable repo + tag.

- **Delivered by**: FG-003
- **Covered by**: `tests/acceptance/test_FG_003_python-scratch-runtime.sh`

### test.central-script

Single `scripts/test-images.sh [image-dir]` discovers every `images/*/tests/smoke_*.sh` and runs it with the correct `IMAGE_NAME`/`IMAGE_TAG`/`REGISTRY` env from the image's `image.yaml`.

- **Delivered by**: FG-003
- **Covered by**: `tests/acceptance/test_FG_003_python-scratch-runtime.sh`

### publish.matrix-auto-discovery

`.github/workflows/build.yml` matrix job is driven by `scripts/discover-images.sh`, which emits a JSON matrix listing every `images/*/image.yaml`. Adding a new image dir auto-enrolls it in the daily publish pipeline — no workflow edit needed. FG-057 extends the script with a `--filter <pattern>` option so manual dispatches can scope to a subset (exact name / comma list / shell glob); scheduled cron uses the default `all`.

- **Delivered by**: FG-003
- **Extended by**: FG-057 (post-tier filter)
- **Covered by**: `scripts/discover-images.sh` + `.github/workflows/build.yml`, `tests/acceptance/test_FG_057_build-image-filter.sh`

### build.workflow-dispatch-image-filter

Manual `workflow_dispatch` on `build.yml` accepts an `images` input (default `all`). Operator-facing: a dev who just updated beaconry's repo can run `gh workflow run build.yml -f images=beaconry-hub` and get a fresh signed `ghcr.io/bboortz/beaconry-hub:latest` digest within ~2 min, instead of waiting for the next 03:00 UTC cron or triggering all 22 images. Filter grammar: exact dir name, comma-separated list, or shell glob (`prometheus-*`, `*-scratch-trixie`). Zero-match filters fail fast with a clear error listing available image dirs. Scheduled cron carries no inputs so the default `all` applies — nightly behaviour unchanged.

- **Delivered by**: FG-057
- **Covered by**: `tests/acceptance/test_FG_057_build-image-filter.sh`, `scripts/discover-images.sh`, `.github/workflows/build.yml`

### image.nginx-serves-http

`nginx-scratch-trixie` answers `curl http://localhost/` with HTTP 200 and the default welcome page out of the box. Minimal self-contained config shipped at `/etc/nginx/nginx.conf`. FG-031 adds a dedicated `location = /healthz { return 200; }` handler plus a baked `HEALTHCHECK` using the embedded `/hc` binary — the image is self-healthchecking without a sidecar.

- **Delivered by**: FG-006
- **Extended by**: FG-031 (`/healthz` endpoint + baked HEALTHCHECK)
- **Covered by**: `tests/acceptance/test_FG_006_nginx-scratch-trixie.sh`, `tests/acceptance/test_FG_031_hc-in-service-images.sh`, `images/nginx-scratch-trixie/tests/smoke_serves_200.sh`, `images/nginx-scratch-trixie/tests/smoke_hc_healthcheck.sh`

### test.smoke-server-helper

`scripts/smoke-server.sh` is the reusable start-wait-probe-stop harness for server images. Takes `--image`, `--port`, `--ready`, `--test`, substitutes `__HOST_PORT__` from the docker-assigned ephemeral host port, polls readiness, runs the test command, always cleans up.

- **Delivered by**: FG-006
- **Covered by**: `tests/acceptance/test_FG_006_nginx-scratch-trixie.sh` (and FG-007 postgres consumes the same helper)

### image.postgres-serves-sql

`postgres-scratch-trixie` starts and answers `psql -c 'SELECT 1'` end-to-end against an externally-initialized cluster. Binary-compatible with Debian postgres data directories (uid 999 pinned to match Docker Hub). FG-026 bumped the postgres major version from 17 → 18. FG-033 adds C.UTF-8 + en_US.UTF-8 locale support, so `initdb --locale=<either>` produces a cluster where `UPPER()`/`LOWER()`/`ORDER BY` respect UTF-8 semantics.

- **Delivered by**: FG-007 (bumped to postgres 18 in FG-026; UTF-8 locales added in FG-033)
- **Covered by**: `tests/acceptance/test_FG_007_postgres-scratch-trixie.sh`, `tests/acceptance/test_FG_033_locale-utf8.sh`, `images/postgres-scratch-trixie/tests/smoke_server_accepts.sh`, `images/postgres-scratch-trixie/tests/smoke_locale_utf8.sh`

### ci.timeout-hardened

Every job in every GHA workflow (`ci.yml`, `build.yml`, `release.yml`, `nightly.yml`) carries an explicit `timeout-minutes` ceiling sized at ~2-3× typical runtime (ci.yml:acceptance-matrix = 10; build.yml:publish-derivatives = 20; nightly.yml:check-strict = 45). Known-flaky steps (`Cache grype DB` via `actions/cache@v4`; `Install supply-chain tools` via Docker Hub pulls) additionally carry step-level `timeout-minutes` + `continue-on-error: true` on the cache step — a stuck cache no longer blocks the job. Replaces GHA's silent 6-hour default. Trigger: 2026-11-09 observed hang on FG-011 matrix cell (Cache grype DB) blocking acceptance-aggregate gate for 20+ min.

- **Delivered by**: FG-038
- **Covered by**: `tests/acceptance/test_FG_038_ci-timeout-hardening.sh`

### image.healthy-sidecar

`healthy-scratch-trixie:2` is the most minimal possible scratch sidecar: raw `FROM scratch` + `/hc` (static Zig healthcheck binary from `bboortz/healthy`) + `/sbom.json`. No libc, no coreutils, no sleep, no wget, no shell, no OS packages at all. Uses `hc idle` (HC-006) as the container PID 1 — a single static binary that blocks on SIGTERM/SIGINT with ~0 CPU. Docker's healthcheck invokes `/hc <url>` via a shared network namespace (`network_mode: service:<name>`). Runs as uid 65532 (distroless nonroot; no /etc/passwd needed since hc doesn't do uid lookups). Image ≤ 1 MB (~400 KB actual) — **10× smaller than `busybox:latest`** (4.2 MB).

- **Delivered by**: FG-030
- **Covered by**: `tests/acceptance/test_FG_030_healthy-scratch-v2.sh`, `images/healthy-scratch-trixie/tests/smoke_sidecar_healthcheck.sh`

### image.locale-utf8

`postgres-scratch-trixie` + `python-scratch-trixie` ship compiled `C.UTF-8` + `en_US.UTF-8` locales at `/usr/lib/locale/C.utf8/` + `/usr/lib/locale/en_US.utf8/` so glibc's `setlocale(LC_ALL, "C.UTF-8")` and `setlocale(LC_ALL, "en_US.UTF-8")` succeed at runtime. Prior to FG-033 both images set `ENV LANG=C.UTF-8` but glibc silently fell back to the `C` locale (postgres reported `lc_ctype=C` from `initdb`; python's `locale.setlocale` raised `locale.Error`). Compiled via `localedef -c -i <base> -f UTF-8 <locale>` in the builder stage — exactly two locales, no full `locale-gen` bloat (~2-3 MB combined vs. ~55 MB for the full Debian locale set). `locale-archive` is included for glibc's fast-path lookup. postgres `initdb --locale=en_US.UTF-8` produces a cluster where `UPPER('ä') = Ä`, `length('€') = 1`, and `ORDER BY` respects Unicode alphabetical order; python's `locale.strcoll` distinguishes byte-order (C.UTF-8) from Unicode-alphabetical (en_US.UTF-8).

- **Delivered by**: FG-033
- **Covered by**: `tests/acceptance/test_FG_033_locale-utf8.sh`, `images/postgres-scratch-trixie/tests/smoke_locale_utf8.sh`, `images/python-scratch-trixie/tests/smoke_locale_utf8.sh`

### image.hc-embedded

The service scratch images that need an HTTP/TCP healthcheck probe carry `/hc` (static Zig binary, ~400 KB, from `ghcr.io/bboortz/hc`) so docker-native `HEALTHCHECK` works in-container — no FG-030 sidecar companion needed. `nginx-scratch-trixie` additionally bakes a `HEALTHCHECK` pointing at a `/healthz` location shipped in its default config. `python-scratch-trixie` carries `/hc` but does NOT bake a HEALTHCHECK (consumer apps vary too much in port + path). The DB/broker trio (redis / postgres / mosquitto) deliberately does not embed `hc` — they ship native CLI tools (`redis-cli PING`, `pg_isready`, `mosquitto_sub -C 1`) that are better-suited. `healthy-scratch-trixie:2` remains published for consumers who prefer the sidecar-netns pattern.

- **Delivered by**: FG-031
- **Covered by**: `tests/acceptance/test_FG_031_hc-in-service-images.sh`, `images/nginx-scratch-trixie/tests/smoke_hc_healthcheck.sh`, `images/python-scratch-trixie/tests/smoke_hc_present.sh`

### image.mosquitto-serves-mqtt

`mosquitto-scratch-trixie:2` starts on `/usr/sbin/mosquitto` (ENTRYPOINT direct, no shell), accepts PUBLISH / SUBSCRIBE via a sidecar container sharing its network namespace, and honors password-file authentication (`allow_anonymous false`). Mosquitto user pinned to uid 1883 (Eclipse convention) — persistent data dirs from existing `eclipse-mosquitto:2` deployments remain mutually readable. Default-permissive config baked at `/mosquitto/config/mosquitto.conf` so config-less `docker run` works for dev; production consumers mount their own at the same path. SIGHUP reloads the config without restarting the broker. Image ≤ 30 MB. Zero OS CVEs.

- **Delivered by**: FG-028
- **Covered by**: `tests/acceptance/test_FG_028_mosquitto-scratch-trixie.sh`, `images/mosquitto-scratch-trixie/tests/smoke_server_accepts.sh`, `images/mosquitto-scratch-trixie/tests/smoke_password_auth.sh`

### image.node-exporter-serves-metrics

`node-exporter-scratch-trixie` runs Prometheus `node_exporter` (Debian `prometheus-node-exporter` package), responds to `GET /metrics` on `:9100` with Prometheus text format. No outbound TLS (scrape-only — the exporter is scraped by prometheus, it doesn't initiate connections). Runs as nonroot uid 65532. Zero OS CVEs (scratch runtime).

- **Delivered by**: FG-034
- **Covered by**: `tests/acceptance/test_FG_034_node-exporter-scratch-trixie.sh`, `images/node-exporter-scratch-trixie/tests/smoke_metrics_endpoint.sh`

### image.prometheus-serves-metrics

`prometheus-scratch-trixie` runs the Prometheus server (Debian `prometheus` package), responds to `/-/healthy` + `/-/ready` + `/api/v1/*` on `:9090`. Serves console_libraries + console_templates for the `/consoles` UI path. Initiates outbound TLS for `remote_write` and alertmanager delivery — the baseline CA bundle resolves via re-declared `ENV SSL_CERT_FILE` (FG-009). Honors SIGHUP for config + rules reload. `promtool` bundled for `docker exec`-based config validation. Runs as nonroot uid 65534 (mutual readability with upstream `prom/prometheus` TSDB volumes). Zero OS CVEs.

- **Delivered by**: FG-035
- **Covered by**: `tests/acceptance/test_FG_035_prometheus-scratch-trixie.sh`, `images/prometheus-scratch-trixie/tests/smoke_healthy_endpoint.sh`

### image.alertmanager-routes-alerts

`alertmanager-scratch-trixie` runs Prometheus Alertmanager, responds to `/-/healthy` + `/-/ready` + `/api/v2/alerts` on `:9093`. Both UIs served from embedded assets: classic Elm UI at `/` + new Mantine UI at `/ui/` (both baked in via `-tags builtinassets`). Initiates outbound HTTPS for every webhook receiver (Telegram, Mattermost, email over SMTPS, generic `webhook_configs`) — the baseline CA bundle resolves via re-declared `ENV SSL_CERT_FILE` (FG-009). Honors SIGHUP for config reload. `amtool` bundled for `docker exec`-based config validation. Runs as nonroot uid 65534. Zero OS CVEs.

- **Delivered by**: FG-036 (Debian-packaged); FG-046 (migrated to from-Go-source); FG-052 (bumped v0.28.1 → v0.35 floating `:latest` via dual-builder for both Elm + Mantine UIs)
- **Covered by**: `tests/acceptance/test_FG_036_alertmanager-scratch-trixie.sh`, `tests/acceptance/test_FG_052_alertmanager-v0.35.sh`, `images/alertmanager-scratch-trixie/tests/smoke_healthy_endpoint.sh`

### image.cadvisor-serves-metrics

`cadvisor-slim-trixie` runs Google cAdvisor (built from Go source at tag `v0.60.6` — upstream doesn't ship the binary via Debian, and their official image is Alpine/musl which doesn't fit Forge's glibc ecosystem). Static Go binary (`CGO_ENABLED=0 -tags netgo`; libpfm deliberately absent — no perf events). Responds to `/healthz` + `/metrics` + `/api/v2/*` on `:8080`. With `-v /sys:/sys:ro -v /:/rootfs:ro -v /var/lib/docker/:/var/lib/docker:ro -v /var/run:/var/run:ro`, exposes per-container CPU / RAM / network / disk metrics alongside the `cadvisor_version_info` identity metric. Runs as root (cgroup read + docker-socket metadata; upstream convention). Shell + apt kept at runtime (slim contract).

- **Delivered by**: FG-044
- **Covered by**: `tests/acceptance/test_FG_044_cadvisor-slim-trixie.sh`, `images/cadvisor-slim-trixie/tests/smoke_metrics_endpoint.sh`

### image.uptime-kuma-serves-monitoring

`uptime-kuma-slim-trixie` runs Uptime Kuma (built from Node source on `node:22-trixie-slim`; upstream only ships a 1664 MB Alpine/Chromium-bundled image). Tracks upstream's latest GitHub release at build time (FG-013 ref:latest pattern). Serves the Vue SPA + REST API on `:3001`; first-run boot lands on a `/setup-database` wizard then transitions to the full dashboard. Supports HTTP/TCP/DNS/Push/Ping monitors (browser-based Playwright monitors deliberately excluded — see `image.uptime-kuma-no-chromium`). SQLite state persists under `/app/data` (named volume expected). HEALTHCHECK polls `/api/entry-page` which stays 200 whether setup is complete or pending. Runs as uid 1000 (`node` user, upstream convention). Shell + apt kept at runtime.

- **Delivered by**: FG-045
- **Covered by**: `tests/acceptance/test_FG_045_uptime-kuma-slim-trixie.sh`, `images/uptime-kuma-slim-trixie/tests/smoke_serves_200.sh`

### image.uptime-kuma-no-chromium

`uptime-kuma-slim-trixie` deliberately does NOT bundle Chromium or Playwright browsers (saves ~200 MB vs upstream). Browser-based synthetic monitors are out of scope for this slim variant — operators who need them run upstream's `louislam/uptime-kuma` OR a future `uptime-kuma-browser-slim-trixie` sibling image. Smoke tests assert `/usr/bin/chromium`, `/usr/bin/chromium-browser`, `/usr/bin/chrome`, `/opt/google/chrome/chrome`, `/ms-playwright`, and `~/.cache/ms-playwright` are all absent — prevents a future apt install accidentally re-introducing them.

- **Delivered by**: FG-045
- **Covered by**: `images/uptime-kuma-slim-trixie/tests/smoke_no_chromium.sh`

### image.uptime-kuma-nonroot

`uptime-kuma-slim-trixie` runs as uid 1000 (upstream's `node` user). Docker Config.User == `node`. No root required — Uptime Kuma is a userspace Node.js app with no special privileges. Named volume on `/app/data` must be chown-able by 1000.

- **Delivered by**: FG-045
- **Covered by**: `images/uptime-kuma-slim-trixie/tests/smoke_user_node.sh`

### image.ipmi-exporter-serves-metrics

`ipmi-exporter-slim-trixie` (FG-037) + `ipmi-exporter-scratch-trixie` (FG-043) — both variants run the Prometheus IPMI exporter (Debian `prometheus-ipmi-exporter`). Scratch variant bundles 5 ELF freeipmi tools (bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi, ipmi-sel) at 36.9 MB; slim bundles the full freeipmi-tools package + shell + apt at 107 MB. Both respond to `GET /metrics` on `:9290` even without `/dev/ipmi0` access (self-metrics only). With `--device /dev/ipmi0` or a `config.yml` carrying remote BMC credentials, scrapes fan speeds, voltages, temperatures, power-draw via IPMI. Both run as root — `/dev/ipmi0` requires it. FG-037's framing that scratch was impractical turned out wrong on deep inspection (the exporter exec's only ELF binaries; the shell-script `ipmimonitoring` is a wrapper it doesn't call).

- **Delivered by**: FG-037 (slim)
- **Extended by**: FG-043 (scratch variant alongside slim)
- **Covered by**: `tests/acceptance/test_FG_037_ipmi-exporter-slim-trixie.sh`, `tests/acceptance/test_FG_043_ipmi-exporter-scratch-trixie.sh`, `images/ipmi-exporter-slim-trixie/tests/smoke_metrics_endpoint.sh`, `images/ipmi-exporter-scratch-trixie/tests/smoke_metrics_endpoint.sh`

### image.ipmi-exporter-scratch-nonroot-exempt

Documented exception to the scratch-image-runs-nonroot default (every other scratch image uses baseline uid 65532). `ipmi-exporter-scratch-trixie` runs as **root** because `/dev/ipmi0` kernel-level device permissions are `root:root` on every Debian host; running non-root would require host-side `chgrp ipmi /dev/ipmi0` + user-group setup that breaks turnkey deployment. Non-root is impossible without host coordination. Explicit documentation prevents future scratch-image audits from mis-flagging this as a regression.

- **Delivered by**: FG-043
- **Covered by**: `images/ipmi-exporter-scratch-trixie/tests/smoke_user_root.sh`

### image.has-shell

Positive-form contract that a Forge image **keeps** a shell at runtime (counterpart to `image.no-shell`). Applies to `-slim` variants: `python-slim-trixie`, `postgres-slim-trixie`, `ipmi-exporter-slim-trixie`, `cadvisor-slim-trixie`, `uptime-kuma-slim-trixie`. Guarantees `/bin/sh` + `apt` + coreutils are present for operator ergonomics (`docker exec -it <container> sh`, interactive debugging, in-container package management). The attack-surface trade-off is explicit — slim images accept nonzero CVE counts in their `scan-baseline.json`.

- **Delivered by**: FG-001 (python-slim-trixie first established the pattern); FG-026 extended to postgres-slim-trixie; FG-037 extends to ipmi-exporter-slim-trixie; FG-044 extends to cadvisor-slim-trixie; FG-045 extends to uptime-kuma-slim-trixie; FG-051 extends to ubuntu-slim-noble + github-runner-noble
- **Covered by**: `images/python-slim-trixie/tests/smoke_entrypoint.sh`, `images/postgres-slim-trixie/tests/smoke_entrypoint_shell.sh`, `images/ipmi-exporter-slim-trixie/tests/smoke_has_shell.sh`, `images/cadvisor-slim-trixie/tests/smoke_has_shell.sh`, `images/uptime-kuma-slim-trixie/tests/smoke_has_shell.sh`, `images/ubuntu-slim-noble/tests/smoke_ca_bundle.sh`, `images/github-runner-noble/tests/smoke_tools_present.sh`

### image.redis-serves-cache

`redis-scratch-trixie:8` starts on `redis-server` (ENTRYPOINT direct, no shell entrypoint script), accepts PING / SET / GET end-to-end via a sidecar container sharing its network namespace (standard pattern for protected-mode). Redis user pinned to uid 999 (Docker Hub convention). Image ≤ 50 MB. Zero OS CVEs (no dpkg database in the runtime). Enables homelab/nextcloud cache deployment with a 1-line adoption diff.

- **Delivered by**: FG-027
- **Covered by**: `tests/acceptance/test_FG_027_redis-scratch-trixie.sh`, `images/redis-scratch-trixie/tests/smoke_server_accepts.sh`

### image.postgres-slim-nextcloud-compatible

`postgres-slim-trixie` is a Debian-trixie-based PostgreSQL 18 image that preserves the upstream `postgres:18` entrypoint behavior — `POSTGRES_*_FILE` secrets-from-file handling, `/docker-entrypoint-initdb.d/*.sql` execution, custom config mounts via `postgres -c config_file=...`, and shell-script maintenance hooks (`psql`, `pg_isready`, bash) all work. Consumer-facing counterpart to the minimalist `postgres-scratch-trixie:18`. Enables homelab/nextcloud-style deployments that need the full upstream postgres contract without giving up Forge's signed/scanned/attested supply chain.

- **Delivered by**: FG-026
- **Covered by**: `tests/acceptance/test_FG_026_postgres-18.sh`, `images/postgres-slim-trixie/tests/smoke_entrypoint_shell.sh`, `images/postgres-slim-trixie/tests/smoke_psql.sh`

### test.sidecar-init

Test pattern for images whose one-time initialization needs a shell (e.g. postgres' `initdb` uses `system()` internally). A shelled sidecar image (Docker Hub's `postgres:17`) writes initial state into a named volume; the scratch image then runs against that volume. Documented limitation: scratch images cannot initialize in-container for workflows that invoke a shell.

- **Delivered by**: FG-007
- **Covered by**: `images/postgres-scratch-trixie/tests/smoke_server_accepts.sh`

### build.scratch-baseline

Shared signed foundation for every Forge scratch image. `scratch-base-trixie` ships a documented common standard: dynamic linker, core glibc (sans `libutil.so.1`), TLS trust, common compression, DNS resolution, network-resolution data (`/etc/services` + `/etc/protocols` + `/etc/hosts`), `/etc/localtime` → UTC, zoneinfo, standard identities (root + nonroot 65532 + nobody), and writable `/tmp` + `/var/tmp` + `/nonroot`. See `docs/specs/baseline-contract.md` for the authoritative API. Derivatives preserve their literal `FROM scratch` runtime line and compose via `COPY --from=scratch_base / /` + an image-specific overlay.

- **Delivered by**: FG-005
- **Extended by**: FG-008 (nonroot identity + network data + /etc/localtime + /var/tmp)
- **Covered by**: `tests/acceptance/test_FG_005_scratch-base-trixie.sh`, `tests/acceptance/test_FG_008_baseline-standard.sh`

### test.scratch-contents

Scratch images have no exec, so smoke suites validate contents by extracting the image via `docker save | tar tf` and asserting required paths are present (or absent). Reusable pattern for any image without a shell / binary that can be probed interactively.

- **Delivered by**: FG-005
- **Extended by**: FG-008 (users/network/time/writable-dirs contracts)
- **Covered by**: `images/scratch-base-trixie/tests/smoke_contents_*.sh`

### docs.baseline-contract

`docs/specs/baseline-contract.md` documents the file-layout API, reserved UIDs, composition contract, ENV re-declaration requirement, non-guarantees, and versioning policy for `scratch-base-trixie`. Authoritative audit surface for current and future consumers of Forge scratch images.

- **Delivered by**: FG-008
- **Covered by**: `tests/acceptance/test_FG_008_baseline-standard.sh`

### image.ssl-cert-env

Every Forge scratch derivative re-declares `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` and `ENV SSL_CERT_DIR=/etc/ssl/certs` in its own Dockerfile. Baseline sets them too but ENV directives don't propagate through `COPY --from=scratch_base` — this convention closes the trap that broke HTTPS for every scratch derivative before FG-009. Memory: [`memory/scratch-closures.md`](../memory/scratch-closures.md) § ENV does not propagate.

- **Delivered by**: FG-009
- **Covered by**: `tests/acceptance/test_FG_009_python-scratch-hardening.sh`

### image.python-scratch-nonroot

`python-scratch-trixie` defaults to `USER 65532:65532`, `WORKDIR /nonroot`, `ENTRYPOINT ["/usr/local/bin/python3"]`, `CMD []`, with `PYTHONDONTWRITEBYTECODE=1` + `PYTHONFAULTHANDLER=1` baked. Distroless convention: `docker run <image> script.py` just works; `docker run <image> pip install ...` needs `--entrypoint=pip`. FG-031 adds `/hc` so consumer apps can wire a docker HEALTHCHECK against their own listener without a sidecar. FG-033 adds C.UTF-8 + en_US.UTF-8 locales so `locale.setlocale(locale.LC_ALL, ...)` with either argument succeeds (previously raised `locale.Error` despite the baked `ENV LANG=C.UTF-8`).

- **Delivered by**: FG-009
- **Extended by**: FG-031 (`/hc` present; consumer configures HEALTHCHECK), FG-033 (compiled C.UTF-8 + en_US.UTF-8 locales)
- **Covered by**: `tests/acceptance/test_FG_009_python-scratch-hardening.sh`, `tests/acceptance/test_FG_031_hc-in-service-images.sh`, `tests/acceptance/test_FG_033_locale-utf8.sh`, `images/python-scratch-trixie/tests/smoke_user_nonroot.sh`, `images/python-scratch-trixie/tests/smoke_tls_https_real.sh`, `images/python-scratch-trixie/tests/smoke_entrypoint.sh`, `images/python-scratch-trixie/tests/smoke_hc_present.sh`, `images/python-scratch-trixie/tests/smoke_locale_utf8.sh`

### contracts.promises

Every image declares what it guarantees to consumers in a machine-checkable `images/<name>/PROMISES.yaml` file. Each promise carries an id, description, CAP cross-references, and a non-empty list of smoke tests that enforce it. `scripts/verify-contracts.py` lints the graph on every CI run.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### contracts.expectations

Every image that depends on another Forge image declares its consumption surface in `images/<name>/EXPECTATIONS.yaml`. Each expectation names (a) the dependency image + version constraint, (b) the specific promise id it relies on, (c) a human-readable reason, (d) preflight smoke test(s) that fail loudly if the baseline ever deviates. The FG-009 ENV-doesn't-propagate trap would have been caught at PR time under this discipline.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### contracts.verify-gate

`make verify-contracts` is a blocking gate in `make check`. It resolves every expectation against its dependency's promises, checks version constraints, and asserts that every test pointer (PROMISES.tests and EXPECTATIONS.preflight) names an existing executable smoke under `images/*/tests/`. Diagnostics are fully qualified — every error names the file, the id, and the referenced thing.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### contracts.semver-enforcement

`scripts/contracts-semver-check.py` runs as a pre-commit hook on `PROMISES.yaml` edits. It classifies each change as `add` (minor), `remove` (major), or `modify` (same id, changed description — requires `--allow-modify` in commit message). Enforces the `version:` bump is at least as large as the change class; refuses commits that silently rot the contract. Removing a promise requires either (a) same-commit update to every dependent EXPECTATIONS.yaml, or (b) `--allow-breaking` override.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### image.manylinux-wheel-compat

`python-scratch-trixie` ships the `/lib/x86_64-linux-gnu/librt.so.1` ABI stub (14.5 KB, as shipped by Debian trixie — empty since glibc 2.34 merged librt into libc). Required so manylinux2014 / manylinux_2_17 wheels (numpy, scipy, pandas, pillow, cryptography, …) that carry `NEEDED librt.so.1` in their ELF dynamic section dlopen successfully at runtime. Baseline is deliberately not affected — this is a Python-ecosystem concern.

- **Delivered by**: FG-011
- **Covered by**: `tests/acceptance/test_FG_011_librt-manylinux-compat.sh`, `images/python-scratch-trixie/tests/smoke_librt_manylinux.sh`

### build.external-source

`images/<name>/image.yaml` supports an optional `source:` block (`git` + `ref` + optional `dockerfile` + `context`). When present, `scripts/build-image.sh` clones the upstream repo at the resolved sha and builds from there — the Dockerfile + sources live upstream, Forge supplies the scan + sign + publish pipeline. `ref` accepts commit sha, git tag, `latest` keyword, or any branch name; always resolves to a concrete sha, baked into `org.opencontainers.image.revision` + `org.opencontainers.image.source` labels via `docker build --label`. Lint (`scripts/verify-image-dirs.sh`) rejects dirs with both `source:` and a local `Dockerfile`.

- **Delivered by**: FG-012
- **Covered by**: `tests/acceptance/test_FG_012_external-sourced-images.sh`

### publish.external-image

Forge's scan + sign + attest + publish pipeline (per-image smokes, grype scan, syft SBOM, cosign keyless signature) applies equally to externally-sourced images. Consumers verify an externally-sourced digest with the same `cosign verify --certificate-identity …/build.yml@refs/heads/main …` command.

- **Delivered by**: FG-012
- **Covered by**: `tests/acceptance/test_FG_012_external-sourced-images.sh`

### image.beaconry-scout

`beaconry-scout` (bb-claw/beaconry → `poc/scout/Dockerfile`) published by Forge as `ghcr.io/bboortz/beaconry-scout:<ver>`. Composed on `python-scratch-trixie:3.14` — inherits every FG-009 guarantee (nonroot, no shell, SSL_CERT_FILE, ENTRYPOINT=python3). Boots a uvicorn FastAPI app on :8001 serving `/healthz` + `/readyz`.

- **Delivered by**: FG-012
- **Covered by**: `tests/acceptance/test_FG_012_external-sourced-images.sh`, `images/beaconry-scout/tests/smoke_http_healthz.sh`

### image.beaconry-scout-bundled-syft

`beaconry-scout` ships `/usr/local/bin/syft` ready to invoke. Scout uses it to generate SBOMs for discovered containers at scan time; consumers can also invoke it directly via `docker run --entrypoint=/usr/local/bin/syft`.

- **Delivered by**: FG-012
- **Covered by**: `images/beaconry-scout/tests/smoke_syft_bundled.sh`

### image.beaconry-hub

`beaconry-hub` (bb-claw/beaconry → `poc/hub/Dockerfile`) published by Forge as `ghcr.io/bboortz/beaconry-hub:<ver>`. Composes on `python-scratch-trixie:3.14` — inherits every FG-009 guarantee. Boots a uvicorn FastAPI app on :8000 serving `/healthz` + `/readyz`. Tracks beaconry `main` via `ref: latest`.

- **Delivered by**: FG-014
- **Covered by**: `tests/acceptance/test_FG_014_beaconry-hub.sh`, `images/beaconry-hub/tests/smoke_http_healthz.sh`

### image.beaconry-hub-bundled-tools

`beaconry-hub` ships three CLIs ready to invoke: `/usr/local/bin/docker` (29.9.2), `/usr/local/bin/grype`, `/usr/local/bin/syft`. Hub uses docker for its `DockerAdapter` (BC-009), grype for CVE waterfall matching, and syft for post-fix SBOM re-verification.

- **Delivered by**: FG-014
- **Covered by**: `images/beaconry-hub/tests/smoke_docker_bundled.sh`, `images/beaconry-hub/tests/smoke_grype_bundled.sh`, `images/beaconry-hub/tests/smoke_syft_bundled.sh`

### image.beaconry-telegram-mock

`beaconry-telegram-mock` (bb-claw/beaconry → `poc/telegram_mock/Dockerfile`) published by Forge as `ghcr.io/bboortz/beaconry-telegram-mock:<ver>`. Test fixture: mock Telegram Bot API shim + BC-018 test-driver surface (`/__driver__/*`) used by beaconry's e2e harness. Unlike scout/hub, base is `python:3.12-slim` (not scratch) — acceptable for a test-only image; Forge still attaches the grype scan attestation. Tracks beaconry `main` via `ref: latest`.

- **Delivered by**: FG-015
- **Covered by**: `tests/acceptance/test_FG_015_beaconry-telegram-mock.sh`, `images/beaconry-telegram-mock/tests/smoke_http_mock.sh`, `images/beaconry-telegram-mock/tests/smoke_driver_api.sh`

### tooling.smart-check

Scope-aware pre-push gate (`make check-smart-strict`, implemented by `scripts/smart-check.sh` + `scripts/affected_images.py`). Reads `git diff $BASE..HEAD`, derives the affected image set (direct path match + FG-010 EXPECTATIONS fan-out on promise-removal/modification + FG-059 Dockerfile FROM-graph fan-out), and runs only that scoped build+smoke+acceptance. Full-run bailouts: `Makefile`, `.pre-commit-config.yaml`, `.github/workflows/*`, `images/scratch-base-trixie/*`, core `scripts/*` from an explicit allowlist (build-image.sh, affected_images.py, smart-check.sh, discover-images.sh, stamp-image.sh, scan-regression.py, verify-*, install-tool-from-docker.sh, image_from_graph.py, scan-baseline-update.py, smoke-server.sh), or `>4` images affected. Non-core `scripts/*` changes fall through to the normal affected-images path. Dispatch is observable via `SMART_CHECK_DRY_RUN=1`. Dedup under `make check` via `_FORGE_IN_CHECK=1` env.

- **Delivered by**: FG-017
- **Extended by**: FG-059 (Dockerfile FROM-graph fan-out + finer scripts/ triage); FG-060 (parallel fan-out builds via xargs -P)
- **Covered by**: `tests/acceptance/test_FG_017_smart-pre-push.sh`, `tests/acceptance/test_FG_059_smart-check-dep-graph.sh`, `tests/acceptance/test_FG_060_parallel-downstream-builds.sh`

### tooling.unscoped-lint

`make lint` resolves every input via `git ls-files` (not working-tree globs) so pre-push lints exactly the file set CI sees after push. Includes an exec-bit check that rejects any git-tracked `*.sh` without `+x` — closes the "shellcheck silently skips non-executable scripts" hole. Pre-push and CI call the same `make test-fast` target; no scoping, no drift (direct response to homelab's "CI fails lint after local passes" class of bug).

- **Delivered by**: FG-017
- **Covered by**: `tests/acceptance/test_FG_017_smart-pre-push.sh`

### build.pr-ci

On push to `dev` or PR targeting `dev`, build the affected image(s) and run grype against each. Does not push to GHCR. Lives in `.github/workflows/ci.yml` as the full-check job. **FG-018**: PR runs `make check-smart` (scope-aware); push-to-dev runs full `make check`; a `full-check` PR label forces `make check-strict` for cross-cutting changes.

- **Delivered by**: FG-001
- **Extended by**: FG-018 (PR gate uses smart-check)
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`, `tests/acceptance/test_FG_018_ci-uses-smart-check.sh`

### scan.regression-gate

PR fails if grype finds a new CRITICAL CVE in an affected image that isn't in the committed `images/<name>/scan-baseline.json`. Runs per-image inside FG-017's smart-check scoped loop (no full-repo scan overhead). Baseline is CVE-ID-set only (not full grype JSON) so diffs stay readable. `make scan-baseline-update IMAGE_DIR=<name>` regenerates intentionally. Missing baseline auto-bootstraps on first run (Q4). HIGH/MEDIUM/LOW findings are NOT gated (Q1 — avoids waiver thrash on python-slim's ~60 Python-stdlib HIGHs).

- **Delivered by**: FG-019
- **Covered by**: `tests/acceptance/test_FG_019_scan-regression.sh`

### scan.cve-waivers

When a CRITICAL CVE must be accepted (no upstream fix, risk assessed), the image's `PROMISES.yaml` `absence.os-cves` promise gains a `waivers: [{cve, reason, until}]` list. `scripts/verify-contracts.py` validates waiver shape + rejects expired waivers (forces renewal or fix). FG-010's semver gate catches silent waiver removal. Cleaner audit than commit-message overrides.

- **Delivered by**: FG-019
- **Covered by**: `tests/acceptance/test_FG_019_scan-regression.sh`

### scan.sbom-embed

Every Forge-native scratch image carries `/sbom.json` — a CycloneDX SBOM generated by syft **in the builder stage** (where dpkg is present) and `COPY`'d into the dpkg-less scratch runtime. `scripts/scan-regression.py` detects `/sbom.json` and invokes `grype sbom:<path>` so the Debian matcher honors trixie-security backports (e.g. `nginx 1.26.3-3+deb13u10`) instead of falling back to NVD-CPE (which only knows upstream version strings and would false-positive the fix). syft is invoked with `--override-default-catalogers dpkg-db-cataloger` so the SBOM contains only Debian packages (no go-module noise from syft itself, no builder-only tools). Beaconry's externally-sourced images don't carry the embed — scan-regression falls back to image-direct grype for them without error.

- **Delivered by**: FG-020
- **Covered by**: `tests/acceptance/test_FG_020_sbom-embed.sh`

### tooling.ci-build-cache

CI runs persist layer + CVE-DB caches across runs. **FG-021**: `scripts/build-image.sh` supports buildx registry cache via `FORGE_CACHE_FROM_PREFIX` + `FORGE_CACHE_PUSH` env vars; GHA workflows wire per-image `ghcr.io/bboortz/<image>:buildcache` tags (cache-from on all events, cache-to on push + nightly build only — PR events pull-only for fork safety). **FG-022**: `actions/cache@v4` persists `~/.cache/grype` keyed on current UTC date with daily rotation. **FG-023** (stamp-skip): per-image stamp at `.make/stamps/<image>.stamp` lets `build-image.sh` skip `docker build` when inputs are unchanged — deduplicates the ~49 builds per check-smart down to ~6 unique images. Cumulative CI wall-clock drop: typical PR 9 min → 2-5 min with buildx cache alone; intra-run dedup reclaims another 300-400s on cold runners.

- **Delivered by**: FG-021 (buildx cache) + FG-022 (grype DB cache) + FG-023 (stamp-skip)
- **Covered by**: `tests/acceptance/test_FG_021_ci-buildx-cache.sh` + `tests/acceptance/test_FG_023_smart-rebuild-skip.sh`

### build.shared-builder

`ghcr.io/bboortz/forge-builder-python-trixie` is a published builder-base image containing `apt-get upgrade` + CA certificates + syft (`v1.57.0`), FROM `python-slim-trixie` (dogfood — post-FG-042; was `python:3.14-slim-trixie` upstream before). Every Forge-native scratch image's builder stage can `FROM ghcr.io/bboortz/forge-builder-python-trixie:<tag>` instead of repeating the apt + syft install work per-image. Published via a dedicated `publish-builders` tier that runs after `publish-pre-builders` (FG-042) and before `publish-base`. PROMISES: `files.syft-binary`, `files.ca-certificates`, `apt.freshly-upgraded`, `apt.no-cache`, `apt.no-curl`.

- **Delivered by**: FG-025
- **Extended by**: FG-042 (dogfood: now FROMs forge-rooted python-slim-trixie instead of Docker Hub)
- **Covered by**: `tests/acceptance/test_FG_025_forge-builder-python-trixie.sh`, `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh`

### build.pre-builder-tier

Four-tier daily-cron publish ordering (FG-042 raised from three): `publish-pre-builders` → `publish-builders` → `publish-base` → `publish-derivatives`. Each tier gated on the previous completing via `needs:`. The new pre-builders tier publishes forge-rooted slim bases (`debian-slim-trixie`, `debian-slim-sid`, `go-slim-trixie`, `node-slim-trixie`, `python-slim-trixie`, `ubuntu-slim-noble`, `zig-slim-trixie`) before anything FROMs them. Collapses multi-consumer Docker Hub trust anchors to one forge image per family + makes version bumps atomic (bump a pre-builder, every downstream consumer inherits on next cron).

- **Delivered by**: FG-042
- **Extended by**: FG-051 (ubuntu-slim-noble added as Forge's first Ubuntu pre-builder); FG-058 (debian-slim-sid added as escape-hatch pre-builder for CVEs that trixie leaves unfixed); FG-061 (node-slim-trixie added as Node runtime pre-builder); FG-065 (go-slim-trixie added as Go toolchain pre-builder; both forge-builder-{go,node}-trixie dogfood their respective pre-builders; "dedicated-toolchain exemption" retired entirely via `arch.language-family-image-pair` invariant); FG-072 (zig-slim-trixie added as Zig toolchain pre-builder; 7 pre-builders now; FROMs debian-slim-trixie — tarball-install exception since Zig has no Debian-based Docker Hub upstream)
- **Covered by**: `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh`, `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh`, `tests/acceptance/test_FG_058_libxml2-waiver-and-debian-sid-base.sh`, `tests/acceptance/test_FG_061_node-slim-trixie-pre-builder.sh`, `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh`, `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh`, `scripts/discover-images.sh` (pre-builders mode)

### image.forge-rooted-slim-bases

Forge owns the Debian + Python + Ubuntu + Node + Go + Zig slim bases consumed by every other slim / scratch builder image. `debian-slim-trixie` (NEW — FG-042) is FROMed by `cadvisor-slim-trixie` + `ipmi-exporter-slim-trixie` + `zig-slim-trixie` (FG-072 tarball-install exception). `python-slim-trixie` (existing — FG-001, reclassified as pre-builder in FG-042) is FROMed by `forge-builder-python-trixie` (dogfood). `ubuntu-slim-noble` (NEW — FG-051) is FROMed by `github-runner-noble`. `debian-slim-sid` (NEW — FG-058) is an escape-hatch pre-builder with zero consumers today, kept warm for CVEs that trixie leaves unfixed but sid patches at the same SONAME. `node-slim-trixie` (NEW — FG-061) is the Node 24 LTS runtime base FROMed by `uptime-kuma-slim-trixie` (migrated from direct-upstream in FG-061) and `forge-builder-node-trixie` (dogfood FG-065). `go-slim-trixie` (NEW — FG-065) is the Go 1.27 toolchain base FROMed only by `forge-builder-go-trixie` (dogfood). `zig-slim-trixie` (NEW — FG-072) is the Zig 0.17 toolchain base FROMed only by `forge-builder-zig-trixie` (dogfood) — Zig has no Debian-based Docker Hub upstream, so this pre-builder FROMs `debian-slim-trixie` and installs Zig from the ziglang.org tarball (committed SHA256 pin). Each upstream Docker Hub anchor (`debian:trixie-slim`, `debian:sid-slim`, `python:3.14-slim-trixie`, `ubuntu:24.04`, `node:24-trixie-slim`, `golang:1.27-trixie`) is consumed exactly once per daily cron — by the forge pre-builder — instead of in parallel by multiple downstream images. Version drift between consumers of the same family is structurally impossible: one bump propagates atomically. Per the `arch.language-family-image-pair` invariant (FG-065), no exemption to this rule remains. The Zig tarball install is a separate, documented exception captured in `_INTRA_LAYER_EXEMPTIONS` — it still routes through the `debian-slim-trixie` pre-builder, preserving the single-upstream-consumer rule for `debian:trixie-slim`.

- **Delivered by**: FG-042
- **Extended by**: FG-051 (ubuntu-slim-noble added; `_EXPECTED=3`); FG-058 (debian-slim-sid added; `_EXPECTED=4`); FG-061 (node-slim-trixie added; `_EXPECTED=5`); FG-065 (go-slim-trixie added + both forge-builder-{go,node}-trixie dogfood their pre-builders; `_EXPECTED=6`; dedicated-toolchain exemption retired); FG-072 (zig-slim-trixie added; `_EXPECTED` stays at 6 because Zig's FROM is ARG-indirect to debian-slim-trixie; one new `_INTRA_LAYER_EXEMPTIONS` entry)
- **Covered by**: `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh`, `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh`, `tests/acceptance/test_FG_058_libxml2-waiver-and-debian-sid-base.sh`, `tests/acceptance/test_FG_061_node-slim-trixie-pre-builder.sh`, `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh`, `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh`, `images/debian-slim-trixie/tests/smoke_*.sh`, `images/debian-slim-sid/tests/smoke_*.sh`, `images/ubuntu-slim-noble/tests/smoke_*.sh`, `images/node-slim-trixie/tests/smoke_*.sh`, `images/go-slim-trixie/tests/smoke_*.sh`, `images/zig-slim-trixie/tests/smoke_*.sh`

### build.shared-go-builder

`ghcr.io/bboortz/forge-builder-go-trixie:0.1` is a published builder-base image mirroring FG-025's `forge-builder-python-trixie` shape but for Go source builds. FROMs `go-slim-trixie` (dogfood, FG-065 — previously `FROM golang:1.27-trixie` upstream directly) + `apt-get upgrade` + CA certificates + syft + git + curl + jq. PROMISES: `files.go-toolchain` (Go >= 1.27), `files.syft-binary`, `files.ca-certificates`, `files.release-resolve-tools` (git + curl + jq), `apt.freshly-upgraded`, `apt.no-cache`. Daily cron rebuilds `go-slim-trixie` first (publish-pre-builders tier) → this image (publish-builders tier) → every from-Go-source derivative within 24h. Bumping the Go major version is a single `golang:X-trixie` update in `go-slim-trixie/Dockerfile` — all derivatives inherit via the chain. Enables FG-046's one-swing migration of 5 Forge-native Go images off Debian's lagging go1.24.x toolchain.

- **Delivered by**: FG-046
- **Extended by**: FG-065 (dogfoods `go-slim-trixie` instead of FROMing `golang:1.27-trixie` directly; satisfies `arch.language-family-image-pair` invariant); FG-066 (syft via `mirror/syft` instead of `docker.io/anchore/syft`)
- **Covered by**: `tests/acceptance/test_FG_046a_forge-builder-go-trixie.sh`, `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh`, `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh`, `images/forge-builder-go-trixie/tests/smoke_*.sh`

### build.from-go-source

Build pattern for Forge images where we either (a) can't use Debian's packaged binary because it isn't in trixie, or (b) choose not to use it because the Debian-shipped Go stdlib carries CVEs we want to fix faster than Debian backports can land. Shape: multi-stage Dockerfile with a dedicated builder stage that `git clone`s the upstream tagged commit, builds with `CGO_ENABLED=0 -tags netgo` + upstream-mirrored ldflags for a static Go binary, and emits a `/sbom.json` via syft against the source tree. Runtime stage overlays the single `COPY --from=builder` of the binary. FG-044 introduced the pattern (FROM golang:X-trixie direct); FG-046 extracted the shared base `forge-builder-go-trixie` (see `build.shared-go-builder`) and migrated 5 images onto it. Consumers: cadvisor-slim-trixie (FG-044), node-exporter-scratch-trixie, alertmanager-scratch-trixie, ipmi-exporter-scratch-trixie, ipmi-exporter-slim-trixie (FG-046). The last two use a **dual-builder** variant: forge-builder-go-trixie for the Go exporter + forge-builder-python-trixie for Debian's freeipmi-tools C binaries. Prometheus-scratch-trixie deferred (requires React UI npm build pipeline — see IDEAS.md).

- **Delivered by**: FG-044 (cadvisor first consumer)
- **Extended by**: FG-046 (shared base + 4 additional consumers; dual-builder pattern for ipmi-exporter)
- **Covered by**: `tests/acceptance/test_FG_044_cadvisor-slim-trixie.sh`, `tests/acceptance/test_FG_046a_forge-builder-go-trixie.sh`, `images/cadvisor-slim-trixie/tests/smoke_static_binary.sh`

### build.from-node-source

Node.js analog of `build.from-go-source`: multi-stage pattern for Node apps not packaged in Debian. Shape: `FROM node:X-trixie-slim AS builder` → resolve upstream GitHub latest release tag at build time (FG-013 pattern) → `git clone --depth 1 --branch <tag>` → `npm ci` (full deps incl. dev) → `npm run build` (SPA compile, e.g. vite) → `npm prune --omit=dev` → syft SBOM against source tree. Runtime stage is the same `node:X-trixie-slim` + `apt-upgrade` + `ca-certificates` + `dumb-init` + `COPY --from=builder /out/app /app`, running as the upstream `node` user (uid 1000). First consumer: `uptime-kuma-slim-trixie`. Doesn't introduce a `forge-builder-node-trixie` yet — single consumer; promotion trigger same as Go: 2nd Node-source image lands.

- **Delivered by**: FG-045
- **Covered by**: `tests/acceptance/test_FG_045_uptime-kuma-slim-trixie.sh`, `images/uptime-kuma-slim-trixie/tests/smoke_node_version.sh`

### tooling.ci-parallel-tests

The acceptance test suite runs as a GitHub Actions matrix (one job per `tests/acceptance/test_FG_*.sh`) instead of a sequential `make test-acceptance` call. `scripts/discover-tests.sh` emits the matrix JSON from `tests/acceptance/`; CI's `acceptance-matrix` job consumes it via `strategy.matrix.include`. `acceptance-aggregate` is a single pass/fail gate for branch protection. Each matrix job still consumes `tooling.ci-build-cache` (buildx + grype DB cache per-job). Local `make check` + `make check-smart` keep running tests sequentially (FG-023 made that fast enough).

- **Delivered by**: FG-024
- **Covered by**: `tests/acceptance/test_FG_024_parallel-acceptance.sh`

### tooling.dockerfile-conformance

Every `images/*/Dockerfile` follows a parser-friendly, drift-resistant convention enforced by `scripts/verify-dockerfile-conformance.py`. Rules: (a) every `ARG *_REF=` is in a small allowlist (`FORGE_BUILDER_REF`, `FORGE_BUILDER_GO_REF`, `FORGE_BUILDER_NODE_REF`, `SCRATCH_BASE_REF`, `DEBIAN_SLIM_REF`, `DEBIAN_SLIM_SID_REF`, `PYTHON_SLIM_REF`, `UBUNTU_SLIM_NOBLE_REF`, `NODE_SLIM_REF`, `HC_REF`); (b) every `FROM` is either `scratch`, an ARG-indirect `${X}` with a declared ARG default, or a literal upstream in the dedicated-toolchain / pre-builder allowlist (`debian:trixie-slim`, `debian:sid-slim`, `python:3.14-slim-trixie`, `ubuntu:24.04`, `node:24-trixie-slim`, `golang:1.27-trixie`, `postgres:18`); (c) every `COPY --from=<stage>` resolves to an earlier `FROM ... AS <stage>` in the same file; (d) every intermediate `FROM` is named with `AS <stage>`; (e) no intra-layer `FROM` edge (a scratch runtime can't FROM another scratch runtime, pre-builder can't FROM another pre-builder, etc.) — the 5-layer invariant stays downward-only. Wired into pre-commit + `make test-fast`.

- **Delivered by**: FG-064
- **Covered by**: `tests/acceptance/test_FG_064_auto-dep-graph.sh`

### tooling.auto-dep-graph

`docs/specs/image-dependency-graph.md` + `docs/specs/image-dependency-graph.svg` are derived artifacts regenerated by `make dep-graph` from the live FROM-graph of every `images/*/Dockerfile`. `scripts/image_from_graph.py --emit=mermaid` renders a strict 5-layer `graph TD` with subgraphs `L0_upstream` → `L1_prebuilders` → `L2_builders` → `L3_baseline` → `L4_runtimes`. Edges flow downward only. **FG-076 extension**: every edge is classified into one of 5 semantic classes with a (shape, color, width) tuple — see `dep-graph.semantic-edge-styling` below. The markdown emits a **hybrid layout**: `![Image dependency graph](image-dependency-graph.svg)` at the top (so the GitHub mobile app, which does NOT render mermaid code blocks, sees the diagram as an image), followed by a `<details>` block containing the mermaid source. The SVG is rendered by `scripts/mermaid-to-svg.sh` via a pinned Docker image (`minlag/mermaid-cli:11.4.2`). CI gate `make verify-dep-graph-fresh` fails any PR that commits a stale `.md` OR `.svg`. External-sourced images (FG-012 — beaconry-*) have no local Dockerfile; the emitter falls back to `image.yaml` `depends_on` + emits an L0.1 source edge.

- **Delivered by**: FG-064
- **Extended by**: FG-076 (semantic edge styling)
- **Covered by**: `tests/acceptance/test_FG_064_auto-dep-graph.sh`, `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh`

### dep-graph.semantic-edge-styling

**FG-076**: `scripts/image_from_graph.py` classifies every emitted edge into one of 5 semantic classes. Each class has a (shape, color, width) tuple pinned via a mermaid `linkStyle N` directive so GitHub's SVG rendering is deterministic + each edge width is ≥ 3px (≈ 3× the ~1.5px mermaid default):

| # | Class | Shape | Width | Color source |
|---|---|---|---|---|
| 1 | FROM-parent (final-stage; trust + CVEs propagate) | `==>` thick | 5px | tier-of-source |
| 2 | FROM builder-stage (content discarded in child) | `-->` solid | 4px | tier-of-source |
| 3 | COPY --from overlay / tool | `-.->` dashed | 4px | tier-of-source |
| 4 | External upstream image (L0 → L1/exempt L4) | `==>` thick | 5px | red `#D81B60` (fixed) |
| 5 | L0.1 upstream source (git clone / tarball) | `-.->` dashed + dotted dasharray | 3px | orange `#E65100` (fixed) |

Tier-of-source palette (Okabe–Ito-adjacent; colorblind-safe): L0 red `#D81B60`, L0.1 orange `#E65100`, L0.5 yellow `#FBC02D`, L1 green `#43A047`, L2 blue `#1E88E5`, L3 brown `#6D4C41`, L4 dark grey `#424242`. A 5-edge Legend subgraph renders at the top of the mermaid source so operators reading the graph on GitHub see the vocabulary inline. Acceptance test asserts: ≥ 4 distinct shapes emitted + linkStyle count ≥ edge count + every linkStyle index < edge count + every linkStyle hex is from the documented palette + legend subgraph present.

- **Delivered by**: FG-076
- **Covered by**: `tests/acceptance/test_FG_076_dep-graph-edge-styling.sh`, `docs/specs/LAYERING.md` §11

### build.stamp-skip

`scripts/build-image.sh` consults a per-image stamp at `.make/stamps/<image>.stamp` before invoking `docker build`. The stamp is a SHA-256 over (tree hash of `images/<dir>/`, resolved upstream FROM digest via `docker buildx imagetools inspect`, baseline image ID for scratch derivatives, resolved external SHA for FG-012 images). If the stamp matches the current inputs AND `docker image inspect <tag>` succeeds, `docker build` is skipped and the existing daemon image is reused — scan + smoke + verify still run against it. `FORGE_NO_SKIP=1` forces a build. `make check-strict` wipes `.make/stamps/` via `clean-stamps`. Daily `build.yml` cron is unaffected (does not route through check-smart). Upstream-change detection is handled by re-resolving the FROM digest on each stamp check — a mutable tag like `python:3.14-slim-trixie` that gets a new digest invalidates the stamp.

- **Delivered by**: FG-023
- **Covered by**: `tests/acceptance/test_FG_023_smart-rebuild-skip.sh`

### build.ref-latest-release

Build-time pattern for Forge images that track an upstream project's latest GitHub Release tag. Dockerfile declares an empty-default version ARG (e.g. `ARG CADVISOR_VERSION=`); the Dockerfile's builder stage resolves the current release tag via `GET https://api.github.com/repos/<upstream>/releases/latest` + `jq -r .tag_name`, writes it to `/tmp/resolved-version`, and the subsequent build step consumes it. The resolved sha + tag get baked into `org.opencontainers.image.revision` + the SBOM. `image.yaml` carries `tag: "latest"` instead of a numeric major.minor; the 4-tag publish family collapses to `:latest` + `:latest-amd64`. Daily cron re-resolves, so the fleet auto-tracks upstream. Applied only to upstreams with stable release discipline + no config-contract churn between minor versions. Precedent: FG-045 uptime-kuma-slim-trixie first shipped this shape inline as a step of `build.from-node-source`; FG-050 formalizes it as a reusable CAP + extends it to cadvisor-slim-trixie + ipmi-exporter-scratch/slim-trixie.

- **Delivered by**: FG-050 (formalized); FG-045 (first consumer, inline)
- **Extended by**: FG-051 (github-runner-noble resolves `actions/runner` latest release tag); FG-052 (alertmanager-scratch-trixie resolves `prometheus/alertmanager` latest release tag — bumped from pinned v0.28.1 to floating :latest)
- **Covered by**: `tests/acceptance/test_FG_050_freshen-upstream-pins.sh`, `tests/acceptance/test_FG_045_uptime-kuma-slim-trixie.sh`, `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh`, `tests/acceptance/test_FG_052_alertmanager-v0.35.sh`

### build.shared-node-builder

`ghcr.io/bboortz/forge-builder-node-trixie:0.1` is a published builder-base image mirroring FG-046's `forge-builder-go-trixie` shape but for Node builds. FROMs `node-slim-trixie` (dogfood, FG-065 — previously `FROM node:24-trixie-slim` upstream directly) + `apt-get upgrade` + CA certificates + syft + git + curl + jq + make/g++/python3 (native-module rebuild safety-net) + dumb-init + `corepack enable` (npm / pnpm / yarn shims resolve on first invocation from the consumer's `packageManager` field). Daily cron rebuilds `node-slim-trixie` first (publish-pre-builders tier) → this image (publish-builders tier) → every Node-source derivative within 24h. Consumers: prometheus-scratch-trixie (dual-builder: Node UI + Go binary via -tags builtinassets), alertmanager-scratch-trixie (dual-builder: Elm + Mantine UIs + Go binary), and uptime-kuma-slim-trixie (builder stage).

- **Delivered by**: FG-048
- **Extended by**: FG-065 (dogfoods `node-slim-trixie` instead of FROMing `node:24-trixie-slim` directly; satisfies `arch.language-family-image-pair` invariant); FG-066 (syft via `mirror/syft` instead of `docker.io/anchore/syft`)
- **Covered by**: `tests/acceptance/test_FG_048a_forge-builder-node-trixie.sh`, `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh`, `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh`, `images/forge-builder-node-trixie/tests/smoke_*.sh`

### build.from-node-and-go-source

Dual-builder pattern for from-source Go projects whose binary embeds a JavaScript-compiled UI via `//go:embed`. Dockerfile has three stages: (1) UI builder `FROM forge-builder-node-trixie` runs `npm ci && npm run build` + the project's `compress_assets.sh`-equivalent to generate the embed directives in Go; (2) Go builder `FROM forge-builder-go-trixie` takes the source tree (now with compiled UI + embed.go) and runs `go build -tags builtinassets` to produce a self-contained binary; (3) runtime stage FROMs scratch-base-trixie (or slim-trixie variant) and overlays the single binary + any non-embedded assets (templates, console libraries, text configs). First consumer: prometheus-scratch-trixie (FG-048). Second consumer: alertmanager-scratch-trixie (FG-052 — builds both the Elm classic UI + the new Mantine UI from `ui/app/package.json` + `ui/mantine-ui/package.json`).

- **Delivered by**: FG-048
- **Extended by**: FG-052 (alertmanager-scratch-trixie dual-UI build — Elm classic + Mantine)
- **Covered by**: `tests/acceptance/test_FG_048b_prometheus-from-source.sh`, `tests/acceptance/test_FG_052_alertmanager-v0.35.sh`

### build.ubuntu-base-noble

Forge's first Ubuntu-base slim image. `ubuntu-slim-noble` is a pre-builder FROM `ubuntu:24.04` (LTS until April 2029) + `apt-get upgrade` + `ca-certificates` + `libicu74` pre-installed. Ubuntu picked over trixie strictly for the GitHub Actions runner's .NET 6 runtime that requires libicu74 (upstream `installdependencies.sh` only tries libicu70-72, which Debian trixie ships but which apt reports as unsatisfiable for the runner; Ubuntu 24.04 ships libicu74 natively). Composes into the existing publish-pre-builders CI tier alongside `debian-slim-trixie` + `python-slim-trixie`. Ubuntu is a **documented-exception** base family for images with Ubuntu-specific library requirements — the default base family remains Debian trixie (see `memory/design-decisions.md`).

- **Delivered by**: FG-051
- **Covered by**: `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh`, `images/ubuntu-slim-noble/tests/smoke_*.sh`

### image.github-runner-noble-pre-baked

`github-runner-noble` is a consumer-facing pre-baked GitHub Actions self-hosted runner image. FROMs `ubuntu-slim-noble` + bakes the full homelab-compatible CI toolset (hadolint, terraform, shellcheck, make, jq, unzip, python3, pip, git, curl, dumb-init, ansible + vendored `requirements-dev.txt` + `ansible-requirements.yml` collections) + the upstream `actions/runner` binary (resolved via FG-050 `build.ref-latest-release` CAP). `ENTRYPOINT /entrypoint.sh` matches the homelab-current entrypoint behavior: first-start registers via GitHub API; subsequent starts skip to `run.sh`. Replaces homelab's local `build: .` + Dockerfile — homelab consumes `ghcr.io/bboortz/github-runner-noble:latest` directly. Deployment time cut from "build + push on each deploy" to "pull".

- **Delivered by**: FG-051
- **Extended by**: FG-063 (RUNNER_CREDS_DIR env var for narrow credential-volume deploys — supersedes homelab's wrapper-script workaround)
- **Covered by**: `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh`, `tests/acceptance/test_FG_063_runner-creds-dir-env.sh`, `images/github-runner-noble/tests/smoke_*.sh`

### image.github-runner-creds-dir

The `github-runner-noble` entrypoint accepts a `RUNNER_CREDS_DIR` env var that persists runner credentials in an operator-chosen path. When set to something other than the default `/home/runner`, the entrypoint uses a two-phase scheme. **Phase 1** (restart): if `RUNNER_CREDS_DIR/.runner` already exists, symlink each existing credential file (`.runner`, `.credentials`, `.credentials_rsaparams`) from `/home/runner/` into `RUNNER_CREDS_DIR` BEFORE invoking `config.sh` / `run.sh`. Files that don't yet exist in `RUNNER_CREDS_DIR` get NO symlink — pre-creating a dangling symlink crashes `Runner.Listener configure`'s `LoadDefaultUserAgents()` path with `FileNotFoundException`. **Phase 2** (first-start post-config): after `config.sh` writes credentials into `/home/runner/` natively, the entrypoint `mv`'s each regular file into `RUNNER_CREDS_DIR` and replaces it with a symlink. Net effect: credentials persist in the narrow volume across container recreation (survives `docker compose up -d --pull always`); the runner binary tree under `/home/runner/bin/` + `/home/runner/externals/` stays image-layer owned, so forge image bumps propagate every restart. Default (`RUNNER_CREDS_DIR=/home/runner`, unset) is a literal no-op.

- **Delivered by**: FG-063
- **Covered by**: `tests/acceptance/test_FG_063_runner-creds-dir-env.sh`, `images/github-runner-noble/tests/smoke_runner_creds_dir.sh`

### build.go-slim-base

Forge-rooted Go 1.27 toolchain slim pre-builder. `go-slim-trixie` FROMs `golang:1.27-trixie` + `apt-get upgrade` + `ca-certificates` + `dumb-init`. Sits in the `publish-pre-builders` CI tier alongside `debian-slim-trixie`, `debian-slim-sid`, `node-slim-trixie`, `python-slim-trixie`, `ubuntu-slim-noble`. Shipped by FG-065 to close the last remaining "dedicated-toolchain exemption": `forge-builder-go-trixie` now dogfoods `go-slim-trixie` (same pattern as `forge-builder-python-trixie` → `python-slim-trixie` from FG-042). Current consumers: only `forge-builder-go-trixie` (dogfood). Go produces static binaries so there is no need today for Go-runtime slim derivatives; the pre-builder's justification is the `arch.language-family-image-pair` invariant + FBG dogfood.

- **Delivered by**: FG-065
- **Covered by**: `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh`, `images/go-slim-trixie/tests/smoke_*.sh`

### build.zig-slim-base

Forge-rooted Zig 0.17 toolchain slim pre-builder. `zig-slim-trixie` FROMs `${DEBIAN_SLIM_REF}` (forge-rooted `debian-slim-trixie`, not a Zig-upstream — Zig doesn't ship an official Debian-based Docker Hub image) and installs Zig from the official ziglang.org tarball with committed SHA256 verification (`ARG ZIG_VERSION` + `ARG ZIG_SHA256`). Adds `apt-get upgrade` + `ca-certificates` + `dumb-init` + `xz-utils` + `curl` on top. Sits in the `publish-pre-builders` CI tier alongside the other six forge-rooted slim bases. Shipped by FG-072 as the fourth language-family pair (Python, Go, Node, Zig). Chain depth is one hop deeper than Python/Go/Node because of the `debian-slim-trixie` intermediate — still at the 5-hop cap. The `debian-slim-trixie` → `zig-slim-trixie` intra-layer edge is the single narrow Rule 6 exemption in `verify-dockerfile-conformance.py`'s `_INTRA_LAYER_EXEMPTIONS` (justified by preserving FG-042's single-upstream-consumer rule). Current consumers: only `forge-builder-zig-trixie` (dogfood). Zig produces static binaries so no Zig-runtime slim consumer exists today.

- **Delivered by**: FG-072
- **Covered by**: `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh`, `images/zig-slim-trixie/tests/smoke_*.sh`

### build.shared-zig-builder

`ghcr.io/bboortz/forge-builder-zig-trixie:0.1` is a published builder-base image mirroring FG-046's `forge-builder-go-trixie` shape but for Zig source builds. FROMs `zig-slim-trixie` (dogfood per `arch.language-family-image-pair`) + `apt-get upgrade` + CA certificates + syft (via `mirror/syft`) + git + curl + jq. PROMISES: `files.zig-toolchain` (Zig 0.*), `files.syft-binary`, `files.ca-certificates`, `files.release-resolve-tools` (git + curl + jq), `apt.freshly-upgraded`, `apt.no-cache`. Daily cron rebuilds `zig-slim-trixie` first (publish-pre-builders tier) → this image (publish-builders tier) → every from-Zig-source derivative within 24h. Zero consumers today; lands ahead of the first from-Zig-source consumer (hc migration into Forge — follow-up FG). Zig has its own C/C++ compiler frontend (`zig cc`) so `build-essential/g++` are deliberately NOT installed — mirrors `forge-builder-go-trixie`'s minimalism.

- **Delivered by**: FG-072
- **Covered by**: `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh`, `images/forge-builder-zig-trixie/tests/smoke_*.sh`

### arch.language-family-image-pair

Architectural invariant (FG-065): every programming language family in the Forge fleet ships **both** `<lang>-slim-trixie` (forge-rooted slim runtime pre-builder in the `publish-pre-builders` CI tier) **and** `forge-builder-<lang>-trixie` (forge-rooted toolchain builder in `publish-builders`). The builder always dogfoods the pre-builder — `forge-builder-<lang>-trixie` FROMs `<lang>-slim-trixie`, never upstream directly. Satisfying families: Python (FG-001 + FG-025, dogfood FG-042), Node (FG-061 + FG-048, dogfood FG-065), Go (both introduced FG-065), Zig (both introduced FG-072 — first language whose pre-builder FROMs `debian-slim-trixie` because Zig has no Docker Hub upstream; installs from ziglang.org tarball with committed SHA256). Enforced by `scripts/verify-dockerfile-conformance.py` Rules 7 + 8 + 9 (builder's last FROM must be a forge image; literal upstream FROM only in pre-builders + `_UPSTREAM_FROM_RUNTIME_EXEMPTIONS`; no `RUN`/`COPY`/`ADD` HTTP pulls from Docker Hub/ghcr.io/library). Future families (Rust, Ruby, Java, …) land as sibling pairs by convention. The "dedicated-toolchain exemption" callout from earlier FGs is retired entirely — no builder bypasses a pre-builder.

- **Delivered by**: FG-065
- **Extended by**: FG-072 (Zig becomes the 4th satisfying family; introduces the "tarball-install" shape for languages without a Debian-based Docker Hub upstream — codified as a named `_INTRA_LAYER_EXEMPTIONS` entry in the conformance lint)
- **Covered by**: `tests/acceptance/test_FG_065_forge-builder-dogfood-symmetry.sh`, `tests/acceptance/test_FG_072_forge-builder-zig-trixie.sh`, `scripts/verify-dockerfile-conformance.py` (Rules 7/8/9)

### build.debian-sid-base

Forge-rooted Debian sid (unstable) slim pre-builder. `debian-slim-sid` sits in the publish-pre-builders CI tier as infrastructure — zero consumers today, kept warm as an escape hatch for CVEs where trixie's package stays unfixed but sid patches at the same SONAME. Debian sid is a case-by-case exception per `memory/design-decisions.md` § "Exception — Debian sid" (first precedent FG-058); default is still trixie. Policy: downstream images FROM `debian-slim-sid`, not `debian:sid-slim` directly (FG-042 upstream-grep invariant). FG-058's trigger was CVE-2026-6653 libxml2 UAF where sid couldn't help (Debian keeps the vulnerable `.so.2` ABI in both suites), but future CVEs on curl / openssl / zlib etc. where sid DOES ship a `.so.2`-compatible fix become 30-min FGs instead of apt-source gymnastics.

- **Delivered by**: FG-058
- **Covered by**: `tests/acceptance/test_FG_058_libxml2-waiver-and-debian-sid-base.sh`, `images/debian-slim-sid/tests/smoke_*.sh`

### build.node-slim-base

Forge-rooted Node 24 LTS runtime slim pre-builder. `node-slim-trixie` FROMs `node:24-trixie-slim` + `apt-get upgrade` + `ca-certificates` + `dumb-init`. Sits in the `publish-pre-builders` CI tier alongside `debian-slim-trixie`, `debian-slim-sid`, `python-slim-trixie`, `ubuntu-slim-noble`. Replaces the previous informal exemption where `uptime-kuma-slim-trixie`'s runtime stage FROMed `node:24-trixie-slim` directly — FG-061 migrates its runtime onto `${NODE_SLIM_REF}` so the FG-042 single-upstream-consumer invariant holds. `forge-builder-node-trixie` remains the paired dedicated-toolchain exemption (same shape as `forge-builder-go-trixie` with `golang:1.27-trixie`): it uses ARG-indirect `FROM ${NODE_BASE}` which doesn't trip the literal `^FROM node:24-trixie-slim` grep in `verify-no-upstream-drift.sh`. Enables FG-062 `psitransfer-slim-trixie` to land as the second runtime consumer without further infrastructure churn.

- **Delivered by**: FG-061
- **Covered by**: `tests/acceptance/test_FG_061_node-slim-trixie-pre-builder.sh`, `images/node-slim-trixie/tests/smoke_*.sh`

### arch.forge-mirror-image

Architectural invariant (FG-066): `images/mirror/<name>/` is a reserved directory for **forge-signed zero-mod passthroughs** of external upstream tool images. GHCR repo is `ghcr.io/bboortz/mirror/<name>:<tag>`. Dockerfile content is restricted to `FROM`, `ARG`, `LABEL`, and `COPY --from=<stage>` — any `RUN`/`ENV`/`WORKDIR`/`CMD`/`USER`/`ADD`/`EXPOSE`/`HEALTHCHECK`/`VOLUME`/`SHELL`/`STOPSIGNAL`/`ONBUILD`/`ENTRYPOINT` is a lint failure. Enforced by `scripts/verify-dockerfile-conformance.py` **Rule 10**. First member: `mirror/syft` (FG-066). Future members (`mirror/grype`, `mirror/hadolint`, `mirror/terraform`, `mirror/cosign-cli`, …) land per-case and reuse this pattern + the dedicated `publish-mirrors` CI tier. Mirrors are consumed ONLY via `COPY --from=<stage>` (never as FROM parents of runtimes). The only difference from upstream is the forge OCI label metadata + the cosign signature over the forge-built digest.

- **Delivered by**: FG-066
- **Covered by**: `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh`, `scripts/verify-dockerfile-conformance.py` (Rule 10)

### build.mirror-tier

New daily-cron CI publish tier `publish-mirrors` — runs **in parallel with** `publish-pre-builders` (no mutual dependency); both block `publish-builders`. The 4-tier publish ordering from FG-042/FG-061/FG-065 grows to **5 tiers**: `{publish-mirrors ∥ publish-pre-builders}` → `publish-builders` → `publish-base` → `publish-derivatives`. Matrix populated from `scripts/discover-images.sh mirrors` which lists every member of the `images/mirror/*/` directory.

- **Delivered by**: FG-066
- **Covered by**: `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh`, `.github/workflows/build.yml`

### build.mirror-syft

`ghcr.io/bboortz/mirror/syft:<tag>` is a forge-signed zero-mod mirror of `anchore/syft`. Dockerfile is `FROM anchore/syft:latest` + 5 `LABEL` + 2 `ARG` lines — nothing else. Consumed via `COPY --from=syft-src /syft /usr/local/bin/syft` by all three forge-builders (`forge-builder-python-trixie`, `forge-builder-go-trixie`, `forge-builder-node-trixie`). Replaces the previous `_HELPER_UPSTREAM_ALLOWLIST` exemption that allowed `docker.io/anchore/syft:latest` as a literal upstream FROM in builder Dockerfiles. After FG-066, zero forge-published image pulls syft from Docker Hub.

- **Delivered by**: FG-066
- **Covered by**: `tests/acceptance/test_FG_066_forge-mirror-tier-syft.sh`, `images/mirror/syft/tests/smoke_*.sh`

### arch.tier-prefix-convention

Every Forge image belongs to exactly one of the 7 tiers in the layering model, and its tier is encoded in its `images/` path prefix (or flat position). The 4 forge-owned tier prefixes are `mirror/` (L0.5), `pre-builder/` (L1), `builder/` (L2), `base/` (L3); flat `images/<name>/` denotes L4 consumer-facing runtimes. L0 (upstream images) + L0.1 (upstream source repos / tarballs) are external — they are consumed by Forge builds but don't live under `images/`. The retired L4.5 `source/` tier is a lint failure if it resurfaces (Rule 11, FG-067). Full definitions + 🔑 semantic tests + overlap-resolution matrix live in `docs/specs/tier-layering-model.md`. This CAP documents the invariant that tier identity is grep-able from the path alone — operators + tooling never need to consult a sidecar classification set. Current state (post-FG-067): 1 mirror, 7 pre-builders, 4 builders, 2 base-tier images at flat paths (scratch-base-trixie + python-scratch-trixie — renamed by FG-069), ~17 L4 runtimes at flat paths.

- **Delivered by**: FG-067
- **Covered by**: `tests/acceptance/test_FG_067_tier-layering-foundation.sh`, `docs/specs/tier-layering-model.md` §2 + §3

### arch.layer-overlap-resolution

The 7-tier model resolves every possible pair-overlap via an ordered set of semantic tests (so no image can accidentally be classified into two tiers). Tests, ordered top-down, from `docs/specs/tier-layering-model.md` §4: (1) **L0 vs L0.1** — transport: `docker pull` → image (L0), `git clone`/`curl .tar.xz` → source (L0.1). (2) **L0.5 Mirror vs L1 Pre-builder** — Rule 10: zero content modifications → mirror; any `RUN` → pre-builder or lower. (3) **L2 Builder** — "runs at runtime?" — no (only COPY-from target) → builder. (4) **L3 Base vs L4 Runtime** — "has ≥ 1 forge-internal consumer?" — yes → base; zero → runtime. (5) **L4 absorbs both apt-installed AND from-source AND externally-sourced** — construction mechanism is build-time detail; runtime role is the tier semantic. (6) **L0 Upstream image vs everything else** — publish identity: not under `ghcr.io/bboortz/<tier>/` + not a flat forge L4 image → upstream image. This CAP exists so new contributors (and lint authors) can answer "which tier does this image belong to?" in bounded time by executing the tests in order.

- **Delivered by**: FG-067
- **Covered by**: `tests/acceptance/test_FG_067_tier-layering-foundation.sh`, `docs/specs/tier-layering-model.md` §4

### build.l0-1-source-inventory

`scripts/_upstream_sources.py` enumerates every **L0.1 source** — git repository or release tarball — that Forge builds consume at build time. Each entry maps the canonical URL to the list of forge image-dir names (consumers) that reference it. `scripts/verify-source-inventory.py` enforces two-way sync: every `RUN git clone <URL>` + `image.yaml source.git: <URL>` reference in the repo must be in the inventory with the consumer declared; every inventory entry must have at least one declared consumer that actually references the URL. Wired into `make test-fast`. The dep-graph emitter (`scripts/image_from_graph.py`) reads the same inventory and emits an L0.1 subgraph with dashed edges from each source to its consumers — making the "where does this source code come from?" question grep-able + visualizable. Covers 10 sources today: `github.com/bboortz/beaconry` (3 FG-012 consumers), `github.com/google/cadvisor`, `github.com/prometheus/{prometheus,alertmanager,node_exporter}`, `github.com/prometheus-community/ipmi_exporter` (2 consumers), `github.com/tianon/gosu`, `github.com/louislam/uptime-kuma`, `github.com/actions/runner`, `ziglang.org/download`.

- **Delivered by**: FG-068
- **Covered by**: `tests/acceptance/test_FG_068_l0-1-source-tooling.sh`, `scripts/verify-source-inventory.py`

### arch.l4-absorbs-from-source

Architectural invariant (FG-067 docs + FG-068 enforcement): the L4 runtime tier absorbs all from-source and externally-sourced consumer-facing images. The construction mechanism — Debian apt-slim, from-Go-source via `builder/go-trixie`, FG-012 externally-sourced via `image.yaml source:`, or from-Zig-source via `builder/zig-trixie` — is a build-time detail of the derived L4 image. The upstream source repos themselves are classified as L0.1 (external, not under `images/`). This retires the previously-proposed L4.5 `source/` tier and codifies that from-source runtimes publish through the existing `publish-derivatives` CI tier at their flat `ghcr.io/bboortz/<name>:<tag>` paths. Enforced by Rule 11 (FG-067 — no `images/source/` allowed) + `verify-source-inventory.py` (every upstream source has an L0.1 inventory entry).

- **Delivered by**: FG-068
- **Covered by**: `tests/acceptance/test_FG_068_l0-1-source-tooling.sh`, `docs/specs/tier-layering-model.md` §3 L4

### build.base-tier

The L3 base tier formalized by FG-069. Members live at `images/base/<name>/`, publish to `ghcr.io/bboortz/base/<name>:<tag>`, and satisfy two invariants (Rule 12): (a) final-stage FROM is `scratch` — base images are scratch-assembled runtime foundations; (b) at least one forge-internal consumer references the image in its `image.yaml depends_on:`. Current members (post-FG-069): `base/scratch-trixie` (9 consumers — the scratch-runtime overlay) + `base/python-trixie` (3 consumers — beaconry-hub/scout/telegram-mock via FG-012 externally-sourced Dockerfiles). Names drop the redundant `-base-` / `-scratch-` tokens — the tier prefix encodes that semantic (see tier-plan §O2+O3). Published in the existing `publish-base` CI tier; `base/python-trixie` depends on `base/scratch-trixie` via `depends_on:` so build ordering flows through `scripts/build-image.sh`'s recursive dep walk.

- **Delivered by**: FG-069
- **Covered by**: `tests/acceptance/test_FG_069_base-tier-migration.sh`, `scripts/verify-dockerfile-conformance.py` (Rule 12), `images/base/{scratch-trixie,python-trixie}/tests/smoke_*.sh`

### arch.base-tier-images

Architectural invariant: every L3 image lives under `images/base/` (encoded in the directory prefix), has `image:` field in PROMISES.yaml equal to the leaf name only (parallel with `mirror/syft`'s `image: syft`), and is reachable at the canonical `base/<leaf>` path via the tooling (discover-images.sh, verify-contracts.py, image_from_graph.py). **FG-075 extension**: shape-agnostic — base/* can be scratch OR slim. Rule 12 reworked to drop the "FROM scratch" + "≥1 forge-internal consumer" sub-rules; base/* members only need image.yaml (with explicit `repo: base/<name>`) + PROMISES.yaml + CI publishing. **FG-075 rename**: `base/python-trixie` → `base/python-scratch-trixie` for naming symmetry with the new slim sibling `base/python-slim-trixie`.

- **Delivered by**: FG-069
- **Extended by**: FG-075 (shape-agnostic — slim + scratch both allowed; rename for symmetry)
- **Covered by**: `tests/acceptance/test_FG_069_base-tier-migration.sh`, `tests/acceptance/test_FG_075_base-tier-public-api.sh`, `docs/specs/LAYERING.md` §3 L3 + §11

### arch.base-tier-public-api

**FG-075**: `base/*` is Forge's consumer-facing public API; `pre-builder/*`, `builder/*` are forge-internal implementation. Documented in `docs/specs/LAYERING.md` §11 "Public API vs internal implementation". External consumers (homelab, Beaconry, future adopters) should FROM `base/*` or flat L4 images; they may use `mirror/*` via `COPY --from=` for tool passthroughs. Forge reserves the right to refactor internal GHCR paths (as FG-069/FG-070/FG-071 demonstrated) without notice; external consumers on `base/*` + flat L4 are insulated from those moves. No CI gate blocks external consumers from FROMing internal tiers (that's a consumer-side policy call) but the boundary is prominently documented.

- **Delivered by**: FG-075
- **Covered by**: `tests/acceptance/test_FG_075_base-tier-public-api.sh`, `docs/specs/LAYERING.md` §11

### image.python-slim-foundation

**FG-075**: `base/python-slim-trixie` published as a Forge-signed slim Python foundation. Contents: `pre-builder/python-slim-trixie` + `/hc` (static Zig healthcheck binary from `ghcr.io/bboortz/hc`) + `USER 65532` nonroot baseline + `ENTRYPOINT ["python3"]`. Dual duty: final runtime for slim Python apps AND builder stage for consumers who want a scratch runtime via `base/python-scratch-trixie` overlay. External consumers (homelab's 7 bots, Beaconry's upstream) flip their `FROM ghcr.io/bboortz/python-slim-trixie:latest` (pre-FG-070 flat path, frozen) to `FROM ghcr.io/bboortz/base/python-slim-trixie:latest` (new, daily-cron'd) in a paired FG-074 follow-up.

- **Delivered by**: FG-075
- **Covered by**: `tests/acceptance/test_FG_075_base-tier-public-api.sh`, `images/base/python-slim-trixie/PROMISES.yaml`

### image.debian-slim-foundation

**FG-077**: `base/debian-slim-trixie` — slim Debian foundation under the arch.base-tier-public-api contract. Contents: `pre-builder/debian-slim-trixie` + `/hc` + `USER 65532`. No `ENTRYPOINT` (Debian default shell). Current consumers: `cadvisor-slim-trixie`, `ipmi-exporter-slim-trixie` (both with `USER 0` override for root-equivalent runtime needs). Enables future homelab consumers to FROM a public-API Debian runtime without reaching into `pre-builder/*`.

- **Delivered by**: FG-077
- **Covered by**: `tests/acceptance/test_FG_077_base-slim-foundations.sh`, `images/base/debian-slim-trixie/PROMISES.yaml`

### image.ubuntu-slim-foundation

**FG-077**: `base/ubuntu-slim-noble` — slim Ubuntu 24.04 (noble) foundation. Shape mirrors `image.debian-slim-foundation`. Rationale: Ubuntu-specific library dependencies (libicu74) require the Ubuntu base per memory/design-decisions.md § Ubuntu exception. Current consumer: `github-runner-noble` (with `USER 0` override — the GitHub Actions runner startup requires root).

- **Delivered by**: FG-077
- **Covered by**: `tests/acceptance/test_FG_077_base-slim-foundations.sh`, `images/base/ubuntu-slim-noble/PROMISES.yaml`

### image.node-slim-foundation

**FG-077**: `base/node-slim-trixie` — slim Node 24 LTS foundation with `ENTRYPOINT ["node"]` (parallel to `base/python-slim-trixie`'s python3 entrypoint). Current consumer: `uptime-kuma-slim-trixie`. Chain depth lands at 5 hops for Node consumers (at the FG-042 cap) — any future Node scratch runtime would need chain-depth restructuring first.

- **Delivered by**: FG-077
- **Covered by**: `tests/acceptance/test_FG_077_base-slim-foundations.sh`, `images/base/node-slim-trixie/PROMISES.yaml`

### build.pre-builder-migrated

Post-FG-070, the 7 L1 pre-builders live under `images/pre-builder/<name>/` with GHCR paths `ghcr.io/bboortz/pre-builder/<name>:<tag>`. Members: `pre-builder/debian-slim-trixie`, `pre-builder/debian-slim-sid`, `pre-builder/go-slim-trixie`, `pre-builder/node-slim-trixie`, `pre-builder/python-slim-trixie`, `pre-builder/ubuntu-slim-noble`, `pre-builder/zig-slim-trixie`. Each image.yaml carries an explicit `repo: pre-builder/<name>` field (parallel with mirror/+base/ convention) so `image_yaml_repo` returns the canonical nested path, not the leaf. 8 consumer ARG defaults in the forge fleet flip to the new path: `UBUNTU_SLIM_NOBLE_REF` (github-runner-noble), `ZIG_SLIM_REF` (forge-builder-zig-trixie), `PYTHON_SLIM_REF` (forge-builder-python-trixie), `NODE_SLIM_REF` (forge-builder-node-trixie + uptime-kuma-slim-trixie), `GO_SLIM_REF` (forge-builder-go-trixie), `DEBIAN_SLIM_REF` (cadvisor-slim-trixie + ipmi-exporter-slim-trixie + pre-builder/zig-slim-trixie). Homelab coordination paired via FG-074.

- **Delivered by**: FG-070
- **Covered by**: `tests/acceptance/test_FG_070_pre-builder-tier-migration.sh`, `scripts/verify-dockerfile-conformance.py`, `scripts/image_from_graph.py`

### arch.pre-builder-tier-images

Architectural invariant: every `pre-builder/<name>/` L1 image is a thin apt-upgrade layer on an upstream OS base. Shape rules: (a) single-stage Dockerfile with literal `FROM <upstream>` (grep-verified by `verify-no-upstream-drift.sh`), (b) adds only `apt-get upgrade` + `ca-certificates` + `dumb-init`, (c) keeps shell + apt + package manager intact (operators can `docker exec -it <image> sh`), (d) consumed by ≥1 forge image (L2 builder dogfood, L3 base, or L4 slim runtime). Published in the `publish-pre-builders` CI tier. Zig is the one exception — FROM `${DEBIAN_SLIM_REF}` (narrow Rule 6 `_INTRA_LAYER_EXEMPTIONS` entry) because Zig has no Debian-based Docker Hub upstream.

- **Delivered by**: FG-070
- **Covered by**: `tests/acceptance/test_FG_070_pre-builder-tier-migration.sh`, `docs/specs/tier-layering-model.md` §3 L1

### build.builder-migrated

Post-FG-071, the 4 L2 forge-builders live under `images/builder/<lang>-trixie/` with GHCR paths `ghcr.io/bboortz/builder/<lang>-trixie:<tag>`. Members: `builder/python-trixie`, `builder/go-trixie`, `builder/node-trixie`, `builder/zig-trixie`. Each image.yaml carries an explicit `repo: builder/<lang>-trixie` field (parallel with mirror/+base/+pre-builder/ convention). The 11 consumer Dockerfiles that FROM a forge-builder flip their ARG from `FORGE_BUILDER_*_REF` to `BUILDER_<LANG>_REF` and their default from `.../forge-builder-<lang>-trixie:...` to `.../builder/<lang>-trixie:...` (8 python consumers incl. base/*; 7 go consumers; 3 node consumers — set union = 11 unique Dockerfiles). PROMISES/EXPECTATIONS `image:` field uses the leaf name (`python-trixie`) matching the base/mirror convention. Closes the 7-tier physical layout opened by FG-067.

- **Delivered by**: FG-071
- **Covered by**: `tests/acceptance/test_FG_071_builder-tier-migration.sh`, `scripts/verify-dockerfile-conformance.py`, `scripts/image_from_graph.py`

### arch.builder-tier-images

Architectural invariant: every `builder/<lang>-trixie/` L2 image is a language-family toolchain that (a) dogfoods its sibling `pre-builder/<lang>-slim-trixie` (Rule 7 checks last FROM), (b) ships syft from `${SYFT_REF}` (mirror/syft; Rule 9 forbids non-forge Docker Hub pulls), (c) is never a runtime — only COPY-from target in multi-stage builds (consumer runtime stage is scratch or slim). Published in the `publish-builders` CI tier (depends on `publish-pre-builders` + `publish-mirrors`). The flat `forge-builder-<lang>-trixie` naming from FG-025/FG-046/FG-048/FG-072 is retired; tier semantic now lives in the `builder/` path prefix (decision O1 in tier-plan). No `FORGE_BUILDER_*_REF` ARG names remain in any Dockerfile — all 11 consumer slots use `BUILDER_<LANG>_REF`.

- **Delivered by**: FG-071
- **Covered by**: `tests/acceptance/test_FG_071_builder-tier-migration.sh`, `docs/specs/tier-layering-model.md` §3 L2

### image.psitransfer-slim

**FG-078**: `psitransfer-slim-trixie` — self-hosted file-share service rebuilt from `github.com/psi-4ward/psitransfer` on Forge's Node chain. 5-stage Dockerfile: `src` (git clone + resolve SHA to `/app/REVISION`) → `frontend` (Vue 2 webpack bundle via `builder/node-trixie`) → `backend` (prod `npm ci` via `builder/node-trixie`) → `sbom` (syft CycloneDX over backend deps) → `runtime` (`base/node-slim-trixie` + /hc + /data VOLUME + USER 65532 + HEALTHCHECK on `:3000/`). Replaces homelab's local `docker/psitransfer/` recipe; paired homelab PR deletes that dir and flips compose to `image: ghcr.io/bboortz/psitransfer-slim-trixie:latest`. Chain at the FG-042 Node 5-hop cap.

- **Delivered by**: FG-078
- **Covered by**: `tests/acceptance/test_FG_078_psitransfer-slim-trixie.sh`, `images/psitransfer-slim-trixie/PROMISES.yaml`

### arch.alpine-pre-builder

**FG-079**: first Alpine OS family in the Forge fleet. `pre-builder/alpine-3` FROMs `alpine:3` (floating major pin) + runs `apk upgrade --no-cache` + installs `ca-certificates` + `dumb-init` + `update-ca-certificates`. Single-stage. Parallel to `pre-builder/debian-slim-trixie` + `pre-builder/ubuntu-slim-noble` but on apk + musl instead of apt + glibc. `verify-no-upstream-drift _EXPECTED` bumps 6 → 7. No `builder/alpine-*` — L2 builders exist for language families (python/go/node/zig), not OS families.

- **Delivered by**: FG-079
- **Covered by**: `tests/acceptance/test_FG_079_alpine-base-family.sh`, `images/pre-builder/alpine-3/PROMISES.yaml`

### image.alpine-foundation

**FG-079**: `base/alpine-3` — public-API Alpine 3.x foundation. Contents: `pre-builder/alpine-3` + `/hc` + `USER 65532`. No ENTRYPOINT (Alpine busybox shell is the default). Dual duty: final runtime for Alpine-musl apps + builder stage for future scratch-musl overlays. Parallel to `image.{debian,ubuntu}-slim-foundation`. Driver: homelab's `docker/ham-remote/rigctld/` currently FROMs `alpine:latest` unsigned; FG-079 unblocks a follow-up FG that rebuilds that image as `ham-rigctld-alpine-3` on `base/alpine-3`. Also unblocks FG-073 nginx-scratch-alpine (draft).

- **Delivered by**: FG-079
- **Covered by**: `tests/acceptance/test_FG_079_alpine-base-family.sh`, `images/base/alpine-3/PROMISES.yaml`

### image.scratch-alpine-foundation

**FG-080**: `base/scratch-alpine-3` — scratch-musl overlay. Strict-intersection closure (musl loader + libc + CA bundle + nss stubs + /etc identity + UTC zone + /tmp 1777). Consumed via `COPY --from=` by scratch-Alpine runtimes. Parallel to `base/scratch-trixie` for glibc. Rule 12 ✓ — `FROM scratch` final stage + ≥1 forge-internal consumer (`nginx-scratch-alpine`).

- **Delivered by**: FG-080
- **Covered by**: `tests/acceptance/test_FG_080_nginx-scratch-alpine-and-scratch-alpine-base.sh`, `images/base/scratch-alpine-3/PROMISES.yaml`

### image.nginx-scratch-alpine

**FG-080**: `nginx-scratch-alpine` — nginx on Alpine/musl FROM scratch. 4-stage Dockerfile: scratch_base_alpine (overlay source) + builder (base/alpine-3 + apk add nginx + ldd closure) + sbom + runtime (FROM scratch + COPY overlay + COPY builder /out). ~15 MB. Serves on :80; HEALTHCHECK on `/`. Parallel to `nginx-scratch-trixie` (FG-006) for operators wanting a musl-sized runtime. First consumer of `base/scratch-alpine-3`; supersedes the long-draft FG-073.

- **Delivered by**: FG-080 (supersedes FG-073 draft)
- **Covered by**: `tests/acceptance/test_FG_080_nginx-scratch-alpine-and-scratch-alpine-base.sh`, `images/nginx-scratch-alpine/PROMISES.yaml`

### arch.archlinux-pre-builder

**FG-081**: third OS family in the Forge fleet (after Debian + Ubuntu + Alpine). `pre-builder/archlinux` FROMs `archlinux:latest` + runs `pacman -Syu --noconfirm ca-certificates` + `update-ca-trust` + `pacman -Scc --noconfirm` (cache clear). Single-stage. Parallel to `pre-builder/alpine-3` but on pacman + rolling-release. `verify-no-upstream-drift _EXPECTED` bumps 7 → 8. Rolling-release model: daily cron re-resolves `archlinux:latest`; scan-baseline drifts more than any other pre-builder (parallel to `debian-slim-sid`). **Delta vs other pre-builders**: dumb-init not shipped (not in Arch core/extra; AUR-only). No `builder/archlinux-*` — L2 builders exist for language families, not OS families.

- **Delivered by**: FG-081
- **Covered by**: `tests/acceptance/test_FG_081_archlinux-base-family.sh`, `images/pre-builder/archlinux/PROMISES.yaml`

### image.archlinux-foundation

**FG-081**: `base/archlinux` — public-API Arch Linux foundation. Contents: `pre-builder/archlinux` + `/hc` + `USER 65532`. No ENTRYPOINT (Arch's `/bin/bash` is the default). Dual duty: final runtime for Arch apps needing rolling-current packages + builder stage for from-source on Arch's toolchain. Parallel to `image.alpine-foundation`. Driver: homelab's `docker/gamepad/Dockerfile` currently FROMs `archlinux:latest` unsigned for `python-evdev`; FG-081 unblocks a follow-up FG that rebuilds that image as `gamepad-archlinux` on `base/archlinux`.

- **Delivered by**: FG-081
- **Covered by**: `tests/acceptance/test_FG_081_archlinux-base-family.sh`, `images/base/archlinux/PROMISES.yaml`

### arch.verify-no-orphan-smokes

**FG-083**: Every `images/<x>/tests/smoke_*.sh` must be referenced by at least one `tests:` entry in some `PROMISES.yaml`. Catches the "test exists but contract doesn't state what it proves" class — DD-TGD's test→promise direction. FG-082 needed a 4-smoke cleanup because this gate didn't exist. Enforced by `scripts/verify-no-orphan-smokes.py`; wired into `make test-fast`.

- **Delivered by**: FG-083
- **Covered by**: `tests/acceptance/test_FG_083_contract-enforcement.sh`, `scripts/verify-no-orphan-smokes.py`

### arch.verify-cap-has-promise

**FG-083**: Every `image.*` CAP in `docs/specs/CAPABILITIES.md` must be named by at least one `caps:` entry in some `PROMISES.yaml`. Non-`image.*` CAPs (`arch.*`, `build.*`, `ci.*`, `tooling.*`, ...) are meta/architecture invariants and don't require promise coverage. Closes the last CAP⇆PROMISES bidirectional gap left by Rules 1–3 of `verify-traceability.sh`. FG-083 adds Rule 4 to that script.

- **Delivered by**: FG-083
- **Covered by**: `tests/acceptance/test_FG_083_contract-enforcement.sh`, `scripts/verify-traceability.sh` Rule 4

### arch.verify-promises-version-bump

**FG-083**: If a `PROMISES.yaml` gains or loses a promise `- id:` line between base branch and HEAD, its `version:` field must also change. Enforced by `scripts/verify-promises-version-bump.sh` (git-diff-aware; default base `origin/dev`; PR CI picks up `GITHUB_BASE_REF`). Pins the prior-FG convention (minor-bump on additive promise changes) as a rule. FG-082 missed 3 bumps because this gate didn't exist.

- **Delivered by**: FG-083
- **Covered by**: `tests/acceptance/test_FG_083_contract-enforcement.sh`, `scripts/verify-promises-version-bump.sh`

### docs.three-folder-structure

**FG-086**: `docs/` is organised into exactly three sibling subdirectories — `docs/specs/` (canonical rules + contracts), `docs/plan/` (FG-NNN-scoped plans + IDEAS backlog + template), `docs/stories/` (FG-NNN-scoped stories + INDEX + templates + 9-questions). `docs/` top-level contains **no files**. Each subdir has a defined allowed-file-set (open for specs/, pattern-matched for plan/ + stories/). Enforced by `scripts/verify-docs-structure.sh`, wired into `make test-fast`. Full definition + decisions: `docs/specs/docs-structure.md`.

- **Delivered by**: FG-086
- **Covered by**: `tests/acceptance/test_FG_086_docs-structure.sh`, `scripts/verify-docs-structure.sh`

### docs.no-stale-refs-gate

**FG-086**: No active (non-historical) file in the repo may reference the pre-FG-086 doc paths (`docs/CAPABILITIES.md`, `docs/LAYERING.md`, `docs/baseline-contract.md`, `docs/differentiators.md`, `docs/image-dependency-graph.{md,svg}`, `docs/plan/tier-layering-model.md`). Historical `docs/plan/FG-*-plan.md` + `docs/stories/FG-*.md` are frozen-in-time records and are explicitly excluded — their refs describe the state at FG shipping time and must not be rewritten. Enforced by `scripts/verify-docs-structure.sh` Rule 4; wired into `make test-fast`.

- **Delivered by**: FG-086
- **Covered by**: `tests/acceptance/test_FG_086_docs-structure.sh`, `scripts/verify-docs-structure.sh`

### ci.release-via-pr

**FG-087**: `release.yml` promotes dev → main via an auto-merge pull request, not a direct push. Preserves main's branch protection (required status checks like `resolve-pr` attach to PRs, not to pushed commits). Workflow steps: (1) pre-flight dev-CI-green assertion (unchanged), (2) find-or-create PR `dev → main`, (3) enable auto-merge (`gh pr merge --auto --merge`), (4) poll until merged (10-min cap). Eliminates the FG-086 loosen-push-restore recovery pattern.

- **Delivered by**: FG-087
- **Covered by**: `tests/acceptance/test_FG_087_release-via-pr.sh`, `.github/workflows/release.yml`

### ci.affected-only-matrix

**FG-090 / SH-022**: PR-triggered acceptance matrix is scoped to tests that cover images affected by the diff (reuses `scripts/smart-check.sh` + `scripts/affected_images.py`). `push` to `dev` and nightly `check-strict` keep the full 84-cell matrix as the safety net. Three dispatch paths: (1) `full` on tooling/baseline touch → full matrix; (2) `test-fast-only` on docs-only → empty matrix (lint-verify covers it); (3) `scoped` → tests matching any affected image name + framework tests (any test that doesn't reference `images/`). Fail-safe: unexpected dispatch → full matrix.

- **Delivered by**: FG-090
- **Covered by**: `scripts/discover-affected-tests.sh` + `.github/workflows/ci.yml` (discover job) + measured post-adoption PR median delta from the SH-026 11.8 min baseline (shepherd).
