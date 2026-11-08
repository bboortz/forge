---
id: FG-029
slug: healthy-scratch-trixie
status: draft
owner: bboortz
created: 2026-11-08
---

# FG-029 — healthy-scratch-trixie (signed healthcheck sidecar for scratch images)

Four homelab stacks (`nextcloud/web-hc`, `sni-router/*-hc`, `website/*-hc` ×2) currently use `busybox:latest` as a long-running sidecar whose only purpose is to run `wget -qO-` against a scratch service that doesn't carry its own HTTP client. The sidecar shares the service's netns (`network_mode: "service:web"`), sleeps forever, and docker invokes `wget` as the service's healthcheck.

`busybox:latest`:
- Not signed, not scanned, not continuously patched (mutable `:latest` from Docker Hub)
- Includes a full shell + 400+ applets the healthcheck doesn't use
- No Forge supply-chain guarantees

This story ships `ghcr.io/bboortz/healthy-scratch-trixie:1` — a minimal scratch sidecar with just `wget`, `nc`, and `sleep` + Debian CA bundle, following the same scan/sign/attest treatment as every other Forge scratch image. ~5 MB vs busybox's ~4 MB (parity on size with signed supply-chain on top).

Deliberately minimal: no `curl` (its closure drags in ~15 MB of GSSAPI/LDAP/brotli/GnuTLS — defeats the "sidecar should be tiny" principle). Consumers who need curl-grade features can use a different sidecar; the four homelab cases use wget exclusively.

## 9 canonical answers

1. **Who** — Benjamin (homelab maintainer) first, for the 4 existing busybox-sidecar deployments. Secondary: any Forge scratch-image consumer whose runtime doesn't bundle a healthcheck client (nginx-scratch-trixie is the primary pattern — HTTP server with no HTTP client). redis/postgres/mosquitto scratch images already bundle their own clients and don't need this.

2. **When** — Fires anytime a scratch image needs an external healthcheck client. `network_mode: service:<name>` is the canonical topology: the sidecar shares the service's netns so `127.0.0.1` reaches the service directly. The sidecar sleeps forever; docker's healthcheck feature invokes `wget` / `nc` against the shared loopback.

3. **What success looks like**:
   - `ghcr.io/bboortz/healthy-scratch-trixie:1` publishes daily with cosign signature + SBOM + scan attestations.
   - Homelab's `web-hc` image becomes `ghcr.io/bboortz/healthy-scratch-trixie:1`, the `command:` drops the `sh -c "while true..."` wrapper (image's CMD is `["/usr/bin/sleep", "infinity"]` by default), the `healthcheck.test:` line stays identical.
   - `wget`, `nc`, and `sleep` all work shell-free (direct binary invocation via docker's `["CMD", ...]` exec form).
   - Image size ≤ 10 MB.

4. **Urgency** — Quality-of-life for homelab. Not security-critical (busybox is maintained). Adoption value: consistent Forge supply-chain across every image in every homelab stack. Finishes the Forge coverage for scratch-service deployments.

5. **Happy path**:
   1. Forge publishes `healthy-scratch-trixie:1`.
   2. Homelab's `nextcloud/web-hc` (and sibling `-hc` sidecars across sni-router/website) change `image: busybox:latest` → `image: ghcr.io/bboortz/healthy-scratch-trixie:1`.
   3. The `command:` line can be dropped (image CMD provides `sleep infinity`).
   4. Existing `healthcheck.test: ["CMD", "wget", "-qO-", "-T", "5", "http://127.0.0.1/healthz"]` keeps working — `wget` is still on PATH.
   5. `cosign verify` confirms supply chain.

6. **Edge cases / failure modes**:
   - **No shell** — consumers who currently wrap `command: ["sh", "-c", "while true..."]` must switch to `command: ["sleep", "infinity"]` or just delete the line (image's CMD is `["/usr/bin/sleep", "infinity"]` by default).
   - **curl needed** — not supported by this image; closure is too heavy. Document in the image README + point to `python-slim-trixie` (ships curl) or `postgres-slim-trixie` (ships curl too, if the consumer is already in that stack).
   - **TLS verification** — wget uses system CA trust; `/etc/ssl/certs/ca-certificates.crt` is inherited from scratch-base-trixie. HTTPS healthchecks against containers with real certs work out of the box.
   - **Netcat variant** — Debian ships `netcat-openbsd` by default (vs `netcat-traditional`). Install the openbsd variant for `-z` scan mode (TCP port-reachability test). Document that `-z` is supported (not all netcats carry it).

7. **Out of scope**:
   - `curl` (too heavy; defeats "minimal sidecar" principle)
   - `jq`, `yq`, `python`, `openssl` CLI (healthchecks don't need them; add via a different image)
   - MQTT / Redis / Postgres client tools — those scratch images already bundle their own clients
   - Ping / ICMP — requires CAP_NET_RAW; sidecar runs as non-root and shouldn't need it
   - `-slim` variant (no consumer needs docker-exec debugging — the whole point is this is a minimal sidecar; if you need shell, use `debian:trixie-slim`)
   - Multi-arch (amd64-only, same as every other image)

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.healthy-sidecar` — scratch sidecar carrying `wget` + `nc` + `sleep` suitable for `network_mode: "service:<name>"` healthcheck-companion deployments.
   - EXT `image.no-shell` — new scratch image passes `smoke_no_shell.sh`.
   - EXT `image.zero-os-cves` — grype against the runtime finds no OS-level matches (no dpkg database).
   - EXT `scan.sbom-embed` — carries `/sbom.json` per FG-020.
   - EXT `build.two-stage-scratch` — new consumer of the pattern.

## Gherkin acceptance

```
Scenario: healthy-scratch-trixie:1 publishes with the standard Forge triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists wget + netcat-openbsd + coreutils
   And the grype attestation is attached
   And the OS-CVE count is zero

Scenario: image default CMD sleeps forever
  Given forge-local/healthy-scratch-trixie:1
  When the container runs with no args
  Then it does not exit on its own within 5s
   And `docker inspect` reports Cmd = ["/usr/bin/sleep", "infinity"]
   And `docker stop` terminates it within 5s cleanly

Scenario: wget resolves a healthy sidecar-mode target
  Given a container running nginx-scratch-trixie serving /healthz on :8080
   And a sidecar container running healthy-scratch-trixie with network_mode="container:<nginx>"
  When `docker run --entrypoint=/usr/bin/wget <sidecar-image> -qO- -T 5 http://127.0.0.1:8080/healthz` runs via the shared netns
  Then it exits 0 and prints "ok"

Scenario: nc -z TCP port scan succeeds against a live listener
  Given a sidecar sharing netns with a scratch service listening on :1883
  When `nc -z 127.0.0.1 1883` runs from the sidecar
  Then it exits 0

Scenario: image has no shell
  Given the built image
  When the runtime file tree is inspected
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh are all absent

Scenario: image is small
  Given the built image
  When `docker image inspect --format {{.Size}}` is read
  Then it is ≤ 10 MB (10 × 10^6 bytes)

Scenario: SBOM is embedded at /sbom.json
  Given the built image
  When /sbom.json is extracted
  Then it is well-formed CycloneDX
   And it contains components for wget + netcat-openbsd + coreutils

Scenario: homelab adopts healthy-scratch-trixie with a 2-line diff
  Given homelab/docker/nextcloud/docker-compose.yml.j2
  When web-hc.image is changed to ghcr.io/bboortz/healthy-scratch-trixie:1
   And web-hc.command is removed (image CMD provides sleep infinity)
  Then docker compose up succeeds
   And the web service's healthcheck via the shared netns turns green
   And nothing else in the compose changes
```

## References

- Plan: `docs/plan/FG-029-healthy-scratch-trixie-plan.md` (to be created at implementation time)
- Red test: `tests/acceptance/test_FG_029_healthy-scratch-trixie.sh` (to be created at implementation time)
- Capabilities: see `docs/CAPABILITIES.md`
- Homelab touchpoints: `~/git/homelab/docker/{nextcloud,sni-router,website}/docker-compose.yml.j2` (4 instances)
- Pattern precedent: FG-027 redis-scratch-trixie / FG-028 mosquitto-scratch-trixie (minimal scratch with a few native binaries + overlay libs on top of scratch-base-trixie). Smaller still because no server daemon, just utilities.
