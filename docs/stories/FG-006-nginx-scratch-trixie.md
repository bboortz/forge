---
id: FG-006
slug: nginx-scratch-trixie
status: shipped
owner: bboortz
created: 2026-11-04
---

# FG-006 — nginx-scratch-trixie: signed, minimal, no-shell nginx

Publish `ghcr.io/bboortz/nginx-scratch-trixie:1.26` (+ `-amd64`, `:latest`, `:latest-amd64`) — Debian trixie's nginx 1.26.3 on a `FROM scratch` runtime. No shell, no `apt`, no dpkg database. Serves static content and acts as a reverse proxy out of the box. grype against the base layer reports zero Debian-source matches; every CVE a consumer sees is upstream nginx itself.

The second image in the Forge catalogue after python; first non-interpreter server. Introduces `scripts/smoke-server.sh` as a reusable start-wait-probe-stop helper (consumed again by FG-007 postgres).

## 9 canonical answers

1. **Who** — ops teams running nginx for static content or TLS termination who want a signed, minimal base image. Security engineer auditing the attack surface.
2. **When** — PR / pre-push / daily cron matrix (inherits from FG-004).
3. **What success looks like** —
   - `docker run -p 80:80 forge-local/nginx-scratch-trixie:1.26` serves `curl http://localhost:80/` → HTTP 200 with the default welcome page
   - `cosign verify ... nginx-scratch-trixie:1.26` exits 0 after first publish
   - `docker run --rm forge-local/nginx-scratch-trixie:1.26 -v` prints `nginx version: nginx/1.26.3`
   - `docker run --rm forge-local/nginx-scratch-trixie:1.26 -t` validates the shipped config
   - `docker run --rm --entrypoint=/bin/sh ...` fails (no shell)
   - `grype` against the image reports zero `.artifact.type == "deb"` matches
   - Image size ≤ **25 MB**
4. **Urgency** — product tier; delivers the second image family.
5. **Happy path** —
   1. Scaffold `images/nginx-scratch-trixie/` with Dockerfile, image.yaml, minimal self-contained `nginx.conf`, tests/.
   2. Dockerfile is two-stage: builder on `python:3.13-slim-trixie` (same pattern as python-scratch for ldd-closure matching), runtime `FROM scratch`.
   3. COPY list: `/usr/sbin/nginx`, libpcre2 + libzstd + libcrypt + libz (over the baseline python-scratch bits — glibc + ssl + CA + zoneinfo + nss + passwd), minimal `nginx.conf`, default `index.html`, `www-data` user entry.
   4. New `scripts/smoke-server.sh` encapsulates: `docker run -d -p PORT:PORT`, poll a readiness probe, run a test command, stop + remove the container. nginx and postgres both consume it.
   5. Smoke suite: binary-runs, config-validates, serves-200 (via smoke-server.sh), no-shell, zero-OS-CVEs, size ≤ 25 MB.
6. **Edge cases / failure modes** —
   - Missing `libpcre2-8.so.0` → nginx refuses to start with `library not found`.
   - Shipped `nginx.conf` references paths like `/var/cache/nginx` that don't exist → startup fails. Minimal config avoids caches entirely.
   - Default nginx expects `nginx` user; trixie's package uses `www-data` (uid 33). COPY the matching `/etc/passwd`/`/etc/group` entries.
   - Port clash on the local dev host — `smoke-server.sh` picks an ephemeral port via docker's auto-assign.
   - Log files written to disk → nginx dies when the runtime fs is readonly. `nginx.conf` sends `access_log` + `error_log` to `/dev/stdout`/`/dev/stderr`.
   - `/tmp/nginx.pid` requires a writable `/tmp` — scratch needs an explicit `/tmp` directory with 1777 perms (same pattern as python-scratch).
   - IPv6 bind in default config → needs `listen 80;` without `[::]:80`.
7. **Out of scope** — TLS termination tests (requires cert fixtures); modsecurity; nginx+brotli; reverse-proxy integration tests; the eventual `scratch-base-trixie` baseline refactor (FG-005 — lands after this story so FG-005 has multiple variants to factor from).
8. **How we know it's done** — see Gherkin below.
9. **Capabilities** —
   - NEW `image.nginx-serves-http` — nginx-scratch-trixie answers HTTP 200 on `/` out of the box
   - NEW `test.smoke-server-helper` — `scripts/smoke-server.sh` encapsulates start-wait-probe-stop for every server image
   - EXT `image.no-shell`, `image.zero-os-cves`, `test.size-budget` — now apply to nginx too

## Gherkin acceptance

```
Scenario: nginx binary reports version
  Given forge-local/nginx-scratch-trixie:1.26
  When docker run --rm <image> -v runs
  Then exit 0
   And stdout contains "nginx/1.26"

Scenario: nginx validates its shipped config
  Given forge-local/nginx-scratch-trixie:1.26
  When docker run --rm <image> -t runs
  Then exit 0
   And stderr contains "syntax is ok" and "test is successful"

Scenario: nginx serves 200 on /
  Given a running container with -p 80 mapped to an ephemeral host port
  When curl http://localhost:<host-port>/ is issued
  Then the response code is 200
   And the body contains "Welcome to nginx"

Scenario: no shell in nginx-scratch-trixie
  Given the image
  When docker run --rm --entrypoint=/bin/sh ... fails
  Then exit non-zero

Scenario: grype against nginx-scratch-trixie finds zero Debian matches
  Given the image built
  When grype -o json runs
  Then matches[] | select(.artifact.type == "deb" or == "dpkg") | length == 0

Scenario: nginx image size ≤ 25 MB
  Given the built image
  Then docker image inspect size ≤ 25_000_000 bytes

Scenario: scripts/smoke-server.sh is reusable
  Given a start command + readiness probe + test command
  When scripts/smoke-server.sh runs
  Then it starts the container, waits for the probe, runs the test, stops + removes the container
   And aggregate exit code reflects the test command's exit
```

## References

- Plan: [`docs/plan/FG-006-nginx-scratch-trixie-plan.md`](../plan/FG-006-nginx-scratch-trixie-plan.md)
- Red test: [`tests/acceptance/test_FG_006_nginx-scratch-trixie.sh`](../../tests/acceptance/test_FG_006_nginx-scratch-trixie.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
