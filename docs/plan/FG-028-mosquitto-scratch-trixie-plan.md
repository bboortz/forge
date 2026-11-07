# FG-028 — Plan: mosquitto-scratch-trixie

**Story**: [`docs/stories/FG-028-mosquitto-scratch-trixie.md`](../stories/FG-028-mosquitto-scratch-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-028-mosquitto-scratch-trixie`

## Design delta

### `images/mosquitto-scratch-trixie/` (new)

- `image.yaml`: tag `"2"`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage. Builder `FROM forge-builder-trixie` (FG-025) → `apt-get install mosquitto mosquitto-clients` → syft SBOM → runtime scratch overlay.
- Runtime `FROM scratch`: overlay the baseline then mosquitto overlay (mosquitto server + all clients, 7 overlay libs, mosquitto user @ uid 1883, writable /mosquitto/{config,data,log}).
- `config/mosquitto.conf`: default-permissive (`listener 1883`, `allow_anonymous true`) baked at `/mosquitto/config/mosquitto.conf` so config-less `docker run` works; production consumers mount their own.
- `ENTRYPOINT ["/usr/sbin/mosquitto"]`, `CMD ["-c", "/mosquitto/config/mosquitto.conf"]`, `USER 1883:1883`, `WORKDIR /mosquitto`, `EXPOSE 1883`.
- `PROMISES.yaml`: 10 promises spanning runtime binaries, server behavior, password-file auth, user pin, no-shell, default-config, SBOM, TLS, size budget.
- `EXPECTATIONS.yaml`: FG-010 contract on scratch-base-trixie ≥ 0.2.

### Smoke tests (7)

- `smoke_binary_runs.sh` — mosquitto + mosquitto_sub + mosquitto_pub + mosquitto_passwd all v2.x.
- `smoke_server_accepts.sh` — default-config boot, sidecar-netns PUB/SUB round-trip, SIGTERM.
- `smoke_password_auth.sh` — generate passwd via mosquitto_passwd, boot with `allow_anonymous false`, confirm wrong creds rejected (Connection Refused) + correct creds accepted. Captures output into variables (pipefail would mask grep-success-after-nonzero-exit).
- `smoke_user_mosquitto.sh` — /etc/passwd pins mosquitto:x:1883:1883.
- `smoke_no_shell.sh` — /bin/{sh,bash,dash}, /usr/bin/sh absent.
- `smoke_contents.sh` — binaries + default config + /sbom.json + CA bundle + /etc/passwd present; SBOM is valid CycloneDX.
- `smoke_size.sh` — image ≤ 30 MB absolute ceiling (~18 MB in practice).

### Acceptance test

`tests/acceptance/test_FG_028_mosquitto-scratch-trixie.sh` with 5 sections:
1. required files present
2. build succeeds via `scripts/build-image.sh`
3. full smoke suite passes
4. SIGHUP reloads config without restarting the container (unique to mosquitto)
5. image.yaml tag + depends_on correct

### No workflow changes

`.github/workflows/build.yml`'s discover job finds the image dir automatically.

## Alternatives rejected

- **FROM eclipse-mosquitto:2 as base** — Alpine-based; our SBOM tooling + Debian CVE tracking assumes dpkg. Debian native is cleaner.
- **Add a `mosquitto-slim-trixie` variant** — no consumer needs docker-exec debugging today. Add if someone later asks.
- **Pin to a later major (3.x)** — Debian trixie ships mosquitto 2.0.21; homelab currently uses eclipse-mosquitto:2. Matching that major avoids a protocol-handling surprise.
- **Mandatory authenticated-only default config** — breaks the "`docker run <image>` works out of the box" dev-ergonomic. Permissive default + prominent docs.

## Breaking changes

None user-facing. New image, no existing consumers.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass
- FG-028 acceptance test green (5 sections)
- All 7 smoke tests green
- `make test-fast` green (hadolint DL3066 avoided via numeric USER)

## Rollout plan

Lands on `dev` via PR. Promotes to `main` via `release.yml` dispatch. Next 03:00 UTC `build.yml` cron publishes `ghcr.io/bboortz/mosquitto-scratch-trixie:2` + `:latest`.

Homelab adoption diff: single-line FROM swap + drop `apk upgrade`. Password file auth continues to work provided the host-side passwd file is readable by uid 1883.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: mosquitto-scratch-trixie:2 publishes with the standard triple | `tests/acceptance/test_FG_028_mosquitto-scratch-trixie.sh` § 1 | ⏳ |
| Scenario: broker boots + serves PUB/SUB end-to-end | § 3 + smoke_server_accepts.sh | ⏳ |
| Scenario: image has no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: mosquitto user is uid 1883 | § 3 + smoke_user_mosquitto.sh | ⏳ |
| Scenario: password-file auth works | § 3 + smoke_password_auth.sh | ⏳ |
| Scenario: SIGHUP config reload | § 4 | ⏳ |
| Scenario: SBOM is embedded at /sbom.json | § 3 + smoke_contents.sh | ⏳ |
| CAP `image.mosquitto-serves-mqtt` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
| EXT `image.no-shell` + `image.zero-os-cves` + `scan.sbom-embed` + `build.two-stage-scratch` | smokes + scan-baseline | ⏳ |
