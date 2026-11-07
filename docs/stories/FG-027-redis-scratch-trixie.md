---
id: FG-027
slug: redis-scratch-trixie
status: shipped
owner: bboortz
created: 2026-11-07
---

# FG-027 — redis-scratch-trixie (minimal signed Redis 8 for homelab + general cache workloads)

Homelab's `nextcloud/redis/Dockerfile` is `FROM redis:8-alpine` + `RUN apk upgrade --no-cache`. Zero config mounts, zero secrets, zero init scripts, zero shell-based maintenance — just a stateless cache answering `redis-cli ping` healthchecks.

Analysis showed 0 of 7 features need a shell (vs. 3 of 6 for postgres/FG-026). So redis maps cleanly to a scratch runtime without any shelled sidecar plumbing or feature loss. This ships that image.

## 9 canonical answers

1. **Who** — Benjamin (homelab maintainer) first; any downstream consumer that uses redis as a stateless cache + wants Forge's signed/scanned/attested supply chain.

2. **When** — Fires when a consumer reaches for `redis:8-alpine` or `redis:8` and wants a Forge-published alternative. Nextcloud-style cache workloads are the primary target.

3. **What success looks like**:
   - `ghcr.io/bboortz/redis-scratch-trixie:8` publishes daily with cosign signature + SBOM + scan attestations.
   - Homelab's `redis/Dockerfile` becomes a 1-line change (`FROM ghcr.io/bboortz/redis-scratch-trixie:8`), dropping the apk-upgrade step entirely (Forge daily cron handles patching).
   - `redis-cli ping` healthcheck continues to work through a sidecar container sharing the server's netns (standard pattern once protected-mode is in play).
   - `docker exec` debugging is unavailable (no shell) — documented as a known trade-off for scratch.

4. **Urgency** — Quality-of-life for homelab. Not security-critical (homelab's `redis:8-alpine` already receives Alpine's security updates). Adoption value: homelab gets the same signed/scanned guarantees as python-slim + nginx-scratch + postgres-slim.

5. **Happy path**:
   1. Forge publishes `redis-scratch-trixie:8`.
   2. Homelab replaces `FROM redis:8-alpine` + `RUN apk upgrade` with `FROM ghcr.io/bboortz/redis-scratch-trixie:8`.
   3. `cosign verify` confirms supply chain.
   4. `docker compose up redis` starts, healthcheck green.
   5. Nextcloud cache behavior unchanged.

6. **Edge cases / failure modes**:
   - **Protected-mode blocks port-forwarded pings** — redis 8 enables protected-mode by default. `redis-cli ping -h <host> -p <forwarded-port>` from outside fails because the connection appears non-local. Healthchecks must run inside a sidecar sharing the server's netns (standard pattern; documented).
   - **No shell → no `docker exec sh redis` debugging** — a known trade-off of scratch. For operator debugging, run `docker run --rm --network=container:<name> --entrypoint=/usr/bin/redis-cli ghcr.io/bboortz/redis-scratch-trixie:8 MONITOR`.
   - **Persistent RDB/AOF data** — if a consumer mounts `/data`, the uid-999 redis user needs to own it. Document as a mount prerequisite (consumer either chowns the host dir to 999 or uses a named volume).
   - **Config file override** — mounting a config at a chosen path works; invoke via CMD `["/etc/redis/redis.conf"]`.

7. **Out of scope**:
   - A `redis-slim-trixie` variant (no consumer needs docker-exec debugging yet; add if someone later asks).
   - Redis modules (default redis-server binary only; no RedisJSON / RedisSearch / etc. in V1).
   - Redis Cluster / Sentinel helper images (same binaries work for both; consumer brings their own config).
   - Multi-arch (amd64-only, matches every other image).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.redis-serves-cache` — redis-scratch-trixie starts, binds :6379, answers PING / SET / GET end-to-end without a shell anywhere in the image.
   - EXT `image.no-shell` — new scratch image passes `smoke_no_shell.sh`.
   - EXT `image.zero-os-cves` — grype against the runtime finds no OS-level matches (no dpkg database to find them in).
   - EXT `scan.sbom-embed` — redis-scratch-trixie carries `/sbom.json` per FG-020.
   - EXT `build.two-stage-scratch` — new consumer of the pattern.

## Gherkin acceptance

```
Scenario: redis-scratch-trixie:8 publishes with the standard Forge triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists redis 8.x
   And the grype attestation is attached
   And the OS-CVE count is zero

Scenario: redis-server boots and serves clients end-to-end
  Given forge-local/redis-scratch-trixie:8 is built
  When a server container runs on the default command (redis-server)
  Then a sidecar container sharing its netns gets PONG from PING
   And SET/GET round-trip returns the expected value
   And the server exits 0 on docker stop

Scenario: image has no shell
  Given the built image
  When the runtime file tree is inspected
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh are all absent

Scenario: redis user is uid 999 (Docker Hub convention)
  Given the built image
  When /etc/passwd is inspected
  Then redis user is pinned to uid 999 / gid 999 with HOME=/data

Scenario: SBOM is embedded at /sbom.json
  Given the built image
  When /sbom.json is extracted
  Then it is well-formed CycloneDX with redis among the components

Scenario: homelab adopts redis-scratch-trixie with a 1-line diff
  Given homelab/docker/nextcloud/redis/Dockerfile
  When FROM is changed to ghcr.io/bboortz/redis-scratch-trixie:8 and the apk upgrade is dropped
  Then docker compose up redis succeeds
   And the redis-cli ping healthcheck turns green
```

## References

- Plan: `docs/plan/FG-027-redis-scratch-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_027_redis-scratch-trixie.sh`
- Capabilities: see `docs/CAPABILITIES.md`
- Homelab touchpoint: `~/git/homelab/docker/nextcloud/redis/Dockerfile`
