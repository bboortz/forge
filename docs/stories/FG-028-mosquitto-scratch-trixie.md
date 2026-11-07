---
id: FG-028
slug: mosquitto-scratch-trixie
status: shipped
owner: bboortz
created: 2026-11-07
---

# FG-028 — mosquitto-scratch-trixie (minimal signed MQTT broker for homelab + IoT workloads)

Homelab's `homeassistant/mosquitto/Dockerfile` is `FROM eclipse-mosquitto:2` + `apk upgrade --no-cache`. It mounts config + password file + data + log dirs, binds port 1883, and healthchecks with `mosquitto_sub`. Zero shell-based flows, zero init scripts, zero secrets-from-FILE — just mosquitto's native config + volume-based auth.

Analysis of homelab's `homeassistant/mosquitto/docker-compose.yml.j2` + `mosquitto.conf` shows **0 of 7 features need a shell** (same shape as redis/FG-027). Scratch is a direct fit — no slim variant required.

Debian trixie ships `mosquitto 2.0.21-1` (verified via `apt-cache show mosquitto`). Uid pinning to 1883 preserves data-dir compatibility with existing Eclipse-mosquitto deployments.

## 9 canonical answers

1. **Who** — Benjamin (homelab maintainer) first, for `homeassistant/mosquitto` broker. Secondary audience: any IoT/MQTT consumer who currently reaches for `eclipse-mosquitto:2` and wants Forge's signed/scanned supply chain.

2. **When** — Fires when a consumer deploys an MQTT broker as part of an IoT stack (Home Assistant, Zigbee2MQTT, custom sensors). The scratch variant covers the "broker + authenticated clients + persistent store" shape — the most common deployment pattern.

3. **What success looks like**:
   - `ghcr.io/bboortz/mosquitto-scratch-trixie:2` publishes daily with cosign signature + SBOM + scan attestations.
   - Homelab's `homeassistant/mosquitto/Dockerfile` becomes a 1-line change (`FROM ghcr.io/bboortz/mosquitto-scratch-trixie:2`), dropping the apk-upgrade step entirely (Forge daily cron handles patching).
   - `mosquitto_sub`-based healthcheck with password auth keeps working (binary is present; no shell needed).
   - Persistent data volume remains compatible (uid 1883 pinned — matches `eclipse-mosquitto`).
   - `docker exec` debugging is unavailable (no shell in scratch) — documented as a known trade-off.

4. **Urgency** — Quality-of-life for homelab. Not security-critical (eclipse-mosquitto:2 already receives Alpine security updates). Adoption value: homelab finishes migrating its non-third-party stack to Forge.

5. **Happy path**:
   1. Forge publishes `mosquitto-scratch-trixie:2`.
   2. Homelab replaces `FROM eclipse-mosquitto:2` + `RUN apk upgrade` with `FROM ghcr.io/bboortz/mosquitto-scratch-trixie:2`.
   3. `cosign verify` confirms supply chain.
   4. `docker compose up mosquitto` starts; Home Assistant connects and publishes retained topics; `mosquitto_sub` healthcheck answers within 3s.
   5. MQTT broker behavior unchanged — same password_file auth, same persistence, same ports.

6. **Edge cases / failure modes**:
   - **Config required** — upstream `eclipse-mosquitto:2` has a default config that allows anonymous clients on 1883 without a mounted config. Homelab ALWAYS mounts a config. We ship the same default-permissive config baked into the image so a config-less `docker run` still works for development use. Documented in README of the image.
   - **Persistent data permissions** — if a consumer mounts `/mosquitto/data`, the host directory must be chown'd to 1883. Documented as a mount prerequisite (host dir chown OR named volume).
   - **Config reload** — mosquitto supports SIGHUP for config reload. With scratch's lack of shell, operators can still `docker kill --signal=HUP <container>`. Document in the FG-010 PROMISES.
   - **mosquitto_passwd util** — the tool that generates password hashes lives in the `mosquitto-clients` package on Debian. Include it in the image so operators can bootstrap auth from a sidecar (or by re-running the image with `--entrypoint=mosquitto_passwd`).
   - **Protected-mode equivalent** — mosquitto has no default protected-mode. External clients from docker port-forward work without netns tricks. Simpler smoke test than redis.

7. **Out of scope**:
   - A `mosquitto-slim-trixie` variant (no consumer needs docker-exec debugging yet).
   - MQTT bridging / clustering — same binary works for both; consumer brings their own config.
   - Mosquitto's websocket listener on :9001 — supported by the binary (compiled with `--with-websockets` in Debian's build), config-driven; smoke tests cover MQTT :1883 only.
   - Zigbee/matter/SensorML — consumer concern, not Forge's.
   - Multi-arch (amd64-only, matches every other image).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.mosquitto-serves-mqtt` — mosquitto-scratch-trixie starts, binds :1883, accepts a PUBLISH, serves a SUBSCRIBE round-trip end-to-end without a shell anywhere in the image.
   - EXT `image.no-shell` — new scratch image passes `smoke_no_shell.sh`.
   - EXT `image.zero-os-cves` — grype against the runtime finds no OS-level matches (no dpkg database to find them in).
   - EXT `scan.sbom-embed` — mosquitto-scratch-trixie carries `/sbom.json` per FG-020.
   - EXT `build.two-stage-scratch` — new consumer of the pattern.

## Gherkin acceptance

```
Scenario: mosquitto-scratch-trixie:2 publishes with the standard Forge triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists mosquitto 2.x
   And the grype attestation is attached
   And the OS-CVE count is zero

Scenario: mosquitto-server boots and serves MQTT clients end-to-end
  Given forge-local/mosquitto-scratch-trixie:2 is built with the default-permissive config
  When a server container runs on the default command (mosquitto -c /mosquitto/config/mosquitto.conf)
  Then a sidecar container sharing its netns gets a PUBLISH / SUBSCRIBE round-trip via mosquitto_pub / mosquitto_sub
   And the server exits 0 on docker stop

Scenario: image has no shell
  Given the built image
  When the runtime file tree is inspected
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh are all absent

Scenario: mosquitto user is uid 1883 (Eclipse convention)
  Given the built image
  When /etc/passwd is inspected
  Then mosquitto user is pinned to uid 1883 / gid 1883 with HOME=/mosquitto

Scenario: password-file auth works with a mounted config
  Given a password_file generated via mosquitto_passwd mounted at /mosquitto/config/passwd
   And a mosquitto.conf that references it + sets allow_anonymous false
  When a mosquitto_sub client connects with wrong credentials
  Then the server rejects with "Connection Refused: not authorised"
  When a client connects with the right credentials
  Then the subscribe completes

Scenario: SIGHUP config reload
  Given a running mosquitto container
  When docker kill --signal=HUP <container> is sent
  Then the server logs "Reloading config" and stays up (does not restart)

Scenario: SBOM is embedded at /sbom.json
  Given the built image
  When /sbom.json is extracted
  Then it is well-formed CycloneDX with mosquitto among the components

Scenario: homelab adopts mosquitto-scratch-trixie with a 1-line diff
  Given homelab/docker/homeassistant/mosquitto/Dockerfile
  When FROM is changed to ghcr.io/bboortz/mosquitto-scratch-trixie:2 and the apk upgrade is dropped
  Then docker compose up mosquitto succeeds
   And the mosquitto_sub password-auth healthcheck turns green
   And Home Assistant's MQTT integration connects without config changes
```

## References

- Plan: `docs/plan/FG-028-mosquitto-scratch-trixie-plan.md` (to be created at implementation time)
- Red test: `tests/acceptance/test_FG_030_mosquitto-scratch-trixie.sh` (to be created at implementation time)
- Capabilities: see `docs/CAPABILITIES.md`
- Homelab touchpoint: `~/git/homelab/docker/homeassistant/mosquitto/Dockerfile`
- Pattern precedent: FG-027 redis-scratch-trixie (closest architectural match — stateless/stateful-with-mount broker, uid-pinned, scratch-compatible)
