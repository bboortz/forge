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

Daily 03:00 UTC cron (`workflow_dispatch` also available) builds every image with `--pull`, attaches attestations, signs, and pushes.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

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

`.github/workflows/build.yml` matrix job is driven by `scripts/discover-images.sh`, which emits a JSON matrix listing every `images/*/image.yaml`. Adding a new image dir auto-enrolls it in the daily publish pipeline — no workflow edit needed.

- **Delivered by**: FG-003
- **Covered by**: `scripts/discover-images.sh` + `.github/workflows/build.yml`

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

`alertmanager-scratch-trixie` runs Prometheus Alertmanager (Debian `prometheus-alertmanager` package), responds to `/-/healthy` + `/-/ready` + `/api/v2/alerts` on `:9093`. Initiates outbound HTTPS for every webhook receiver (Telegram, Mattermost, email over SMTPS, generic `webhook_configs`) — the baseline CA bundle resolves via re-declared `ENV SSL_CERT_FILE` (FG-009). Honors SIGHUP for config reload. `amtool` bundled for `docker exec`-based config validation. Runs as nonroot uid 65534. Zero OS CVEs.

- **Delivered by**: FG-036
- **Covered by**: `tests/acceptance/test_FG_036_alertmanager-scratch-trixie.sh`, `images/alertmanager-scratch-trixie/tests/smoke_healthy_endpoint.sh`

### image.ipmi-exporter-serves-metrics

`ipmi-exporter-slim-trixie` runs the Prometheus IPMI exporter (Debian `prometheus-ipmi-exporter` package) + bundled `freeipmi-tools` (ipmimonitoring, ipmi-sel, ipmi-dcmi). Responds to `GET /metrics` on `:9290` even without `/dev/ipmi0` access (self-metrics only). With `--device /dev/ipmi0` or a `config.yml` carrying remote BMC credentials, scrapes fan speeds, voltages, temperatures, power-draw via IPMI. Runs as root (upstream + local-BMC device-permission compatibility). **Slim** runtime — not scratch — because `freeipmi-tools`' dynamic C closure makes scratch overlay impractical.

- **Delivered by**: FG-037
- **Covered by**: `tests/acceptance/test_FG_037_ipmi-exporter-slim-trixie.sh`, `images/ipmi-exporter-slim-trixie/tests/smoke_metrics_endpoint.sh`

### image.has-shell

Positive-form contract that a Forge image **keeps** a shell at runtime (counterpart to `image.no-shell`). Applies to `-slim` variants: `python-slim-trixie`, `postgres-slim-trixie`, `ipmi-exporter-slim-trixie`. Guarantees `/bin/sh` + `apt` + coreutils are present for operator ergonomics (`docker exec -it <container> sh`, interactive debugging, in-container package management). The attack-surface trade-off is explicit — slim images accept nonzero CVE counts in their `scan-baseline.json`.

- **Delivered by**: FG-001 (python-slim-trixie first established the pattern); FG-026 extended to postgres-slim-trixie; FG-037 extends to ipmi-exporter-slim-trixie
- **Covered by**: `images/python-slim-trixie/tests/smoke_entrypoint.sh`, `images/postgres-slim-trixie/tests/smoke_entrypoint_shell.sh`, `images/ipmi-exporter-slim-trixie/tests/smoke_has_shell.sh`

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

Shared signed foundation for every Forge scratch image. `scratch-base-trixie` ships a documented common standard: dynamic linker, core glibc (sans `libutil.so.1`), TLS trust, common compression, DNS resolution, network-resolution data (`/etc/services` + `/etc/protocols` + `/etc/hosts`), `/etc/localtime` → UTC, zoneinfo, standard identities (root + nonroot 65532 + nobody), and writable `/tmp` + `/var/tmp` + `/nonroot`. See `docs/baseline-contract.md` for the authoritative API. Derivatives preserve their literal `FROM scratch` runtime line and compose via `COPY --from=scratch_base / /` + an image-specific overlay.

- **Delivered by**: FG-005
- **Extended by**: FG-008 (nonroot identity + network data + /etc/localtime + /var/tmp)
- **Covered by**: `tests/acceptance/test_FG_005_scratch-base-trixie.sh`, `tests/acceptance/test_FG_008_baseline-standard.sh`

### test.scratch-contents

Scratch images have no exec, so smoke suites validate contents by extracting the image via `docker save | tar tf` and asserting required paths are present (or absent). Reusable pattern for any image without a shell / binary that can be probed interactively.

- **Delivered by**: FG-005
- **Extended by**: FG-008 (users/network/time/writable-dirs contracts)
- **Covered by**: `images/scratch-base-trixie/tests/smoke_contents_*.sh`

### docs.baseline-contract

`docs/baseline-contract.md` documents the file-layout API, reserved UIDs, composition contract, ENV re-declaration requirement, non-guarantees, and versioning policy for `scratch-base-trixie`. Authoritative audit surface for current and future consumers of Forge scratch images.

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

Scope-aware pre-push gate (`make check-smart-strict`, implemented by `scripts/smart-check.sh` + `scripts/affected_images.py`). Reads `git diff $BASE..HEAD`, derives the affected image set (direct path match + FG-010 EXPECTATIONS fan-out on promise-removal/modification), and runs only that scoped build+smoke+acceptance. Full-run bailouts: `scripts/*`, `Makefile`, `.pre-commit-config.yaml`, `.github/workflows/*`, `images/scratch-base-trixie/*`, or `>4` images affected. Dispatch is observable via `SMART_CHECK_DRY_RUN=1`. Dedup under `make check` via `_FORGE_IN_CHECK=1` env — acceptance tests' internal `scripts/test-images.sh` invocations are skipped since the global `test-images` phase covers them.

- **Delivered by**: FG-017
- **Covered by**: `tests/acceptance/test_FG_017_smart-pre-push.sh`

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

`ghcr.io/bboortz/forge-builder-trixie` is a published builder-base image containing `apt-get upgrade` + CA certificates + syft (`v1.57.0`), on top of `python:3.14-slim-trixie`. Every Forge-native scratch image's builder stage can `FROM ghcr.io/bboortz/forge-builder-trixie:<tag>` instead of repeating the apt + syft install work per-image. Published via a dedicated `publish-builders` tier that runs before `publish-base` in `build.yml`. PROMISES: `files.syft-binary`, `files.ca-certificates`, `apt.freshly-upgraded`, `apt.no-cache`, `apt.no-curl`.

- **Delivered by**: FG-025 (Phase 1: scratch-base-trixie migration; Phase 2 TBD for python/nginx/postgres)
- **Covered by**: `tests/acceptance/test_FG_025_forge-builder-trixie.sh`

### tooling.ci-parallel-tests

The acceptance test suite runs as a GitHub Actions matrix (one job per `tests/acceptance/test_FG_*.sh`) instead of a sequential `make test-acceptance` call. `scripts/discover-tests.sh` emits the matrix JSON from `tests/acceptance/`; CI's `acceptance-matrix` job consumes it via `strategy.matrix.include`. `acceptance-aggregate` is a single pass/fail gate for branch protection. Each matrix job still consumes `tooling.ci-build-cache` (buildx + grype DB cache per-job). Local `make check` + `make check-smart` keep running tests sequentially (FG-023 made that fast enough).

- **Delivered by**: FG-024
- **Covered by**: `tests/acceptance/test_FG_024_parallel-acceptance.sh`

### build.stamp-skip

`scripts/build-image.sh` consults a per-image stamp at `.make/stamps/<image>.stamp` before invoking `docker build`. The stamp is a SHA-256 over (tree hash of `images/<dir>/`, resolved upstream FROM digest via `docker buildx imagetools inspect`, baseline image ID for scratch derivatives, resolved external SHA for FG-012 images). If the stamp matches the current inputs AND `docker image inspect <tag>` succeeds, `docker build` is skipped and the existing daemon image is reused — scan + smoke + verify still run against it. `FORGE_NO_SKIP=1` forces a build. `make check-strict` wipes `.make/stamps/` via `clean-stamps`. Daily `build.yml` cron is unaffected (does not route through check-smart). Upstream-change detection is handled by re-resolving the FROM digest on each stamp check — a mutable tag like `python:3.14-slim-trixie` that gets a new digest invalidates the stamp.

- **Delivered by**: FG-023
- **Covered by**: `tests/acceptance/test_FG_023_smart-rebuild-skip.sh`
