---
id: FG-016
slug: nginx-stream-modules
status: in-progress
owner: bboortz
created: 2026-11-07
---

# FG-016 — Bundle nginx dynamic modules + `/etc/nginx/mime.types` in nginx-scratch-trixie

Three small additions to `nginx-scratch-trixie:1.26` that let consumers with stream-based nginx configs (SNI dispatchers, L4 proxies) drop in a custom config via docker-compose mount — no derived image needed. Motivated by homelab's `sni-router` ([bb-claw/homelab](https://github.com/bb-claw/homelab)/`docker/sni-router/nginx.conf.j2`): that config uses `stream { map $ssl_preread_server_name ... }`, requires `ngx_stream_module.so` to be loadable + `/etc/nginx/mime.types` to be present.

### Changes

1. `images/nginx-scratch-trixie/Dockerfile`:
   - apt-install `libnginx-mod-stream` alongside `nginx` (brings `ngx_stream_module.so` which also carries `ssl_preread`).
   - COPY `/usr/lib/nginx/modules/*.so` into the scratch overlay.
   - Symlink `/usr/share/nginx/modules → /usr/lib/nginx/modules` so relative `load_module modules/<x>.so;` directives resolve (nginx's compile-time prefix differs from Debian's actual path).
   - COPY `/etc/nginx/mime.types` (~5 KB) — standard-ish file every HTTP config `include`s.
2. `PROMISES.yaml` version 0.1 → 0.2 (contract add — semver-gated minor).
3. New promise `runtime.dynamic-modules`.

### Image impact

- Size: 15.3 MB → 15.6 MB (+200 KB module + 5 KB mime.types). Well within the 25 MB ceiling.
- No functional regression on existing consumers — default `nginx.conf` doesn't `load_module`.

## 9 canonical answers (compressed — surgical delta)

1. **Who** — any consumer with stream-based nginx configs (SNI dispatcher, L4 TLS pass-through, TCP/UDP load balancer); first known case is homelab/sni-router.
2. **When** — on every PR / pre-push / daily cron.
3. **Success** — image bundles `ngx_stream_module.so` + `mime.types`; rendering `homelab/sni-router/nginx.conf.j2` with only 3 trivial homelab-side edits (documented below) passes `nginx -t`.
4. **Urgency** — product tier; unblocks homelab's sni-router migration to Forge's hardened nginx.
5. **Happy path** — see "Changes" above.
6. **Edge cases** —
   - Default config doesn't `load_module` → zero behavior change for `nginx-serves-http`.
   - Future 3rd-party stream modules (e.g. `libnginx-mod-stream-geoip2`) could be added by extending the apt install line; FG-016 only covers the base `libnginx-mod-stream`.
7. **Out of scope** —
   - Making `/var/run` writable (sni-router can use `/tmp` for its pid; that's standard scratch convention).
   - Adding a `nginx` user alias (Debian uses `www-data`; consumers conform).
   - Shipping `mail` or `geoip2` dynamic modules.
8. **Done** — FG-016 acceptance test green + `make check-strict` green.
9. **Capabilities**:
   - EXT `image.nginx-serves-http` — now covers stream-based configs via dynamic modules

### Homelab adoption diff (one-time, 3 lines in sni-router's `nginx.conf.j2`)

```diff
+load_module modules/ngx_stream_module.so;
+
-user  nginx;
+user  www-data;
 worker_processes  auto;
 error_log  /var/log/nginx/error.log notice;
-pid        /var/run/nginx.pid;
+pid        /tmp/nginx.pid;
```

After this diff lands, homelab deletes `docker/sni-router/Dockerfile` entirely and points compose at `ghcr.io/bboortz/nginx-scratch-trixie:1.26`.

## Gherkin acceptance

```
Scenario: dynamic modules bundled
  Given the image
  When I inspect its filesystem
  Then /usr/lib/nginx/modules/ngx_stream_module.so is present
   And /etc/nginx/mime.types is present
   And /usr/share/nginx/modules → /usr/lib/nginx/modules (symlink)

Scenario: sni-router config (with 3-line adoption diff) validates
  Given homelab/sni-router/nginx.conf.j2 rendered with test values + the 3-line adoption diff
  When nginx -t is run against it inside the image
  Then it exits 0 with "syntax is ok" and "test is successful"

Scenario: existing nginx-serves-http unchanged
  Given the default image config (no load_module)
  Then GET / returns 200 as before (regression check)
```

## References

- Plan: [`docs/plan/FG-016-nginx-stream-modules-plan.md`](../plan/FG-016-nginx-stream-modules-plan.md)
- Red test: [`tests/acceptance/test_FG_016_nginx-stream-modules.sh`](../../tests/acceptance/test_FG_016_nginx-stream-modules.sh)
- Smokes: [`smoke_modules_present.sh`](../../images/nginx-scratch-trixie/tests/smoke_modules_present.sh), [`smoke_stream_config_validates.sh`](../../images/nginx-scratch-trixie/tests/smoke_stream_config_validates.sh)
- Downstream consumer: `homelab/sni-router` (bb-claw/homelab)
