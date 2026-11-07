# FG-016 — Plan: nginx stream modules + mime.types

**Story**: [`docs/stories/FG-016-nginx-stream-modules.md`](../stories/FG-016-nginx-stream-modules.md)
**Status**: in-progress
**Branch**: `feat/FG-016-nginx-stream-modules`

## Design delta

```diff
 # images/nginx-scratch-trixie/Dockerfile
-apt-get install nginx ca-certificates
+apt-get install nginx libnginx-mod-stream ca-certificates

 # assembly RUN:
+install -d /out/usr/lib/nginx/modules
+cp /usr/lib/nginx/modules/*.so /out/usr/lib/nginx/modules/
+ln -s /usr/lib/nginx/modules /out/usr/share/nginx/modules   # path reconciliation
+cp /etc/nginx/mime.types /out/etc/nginx/mime.types           # universal include target

 # PROMISES.yaml:
-version: "0.1"
+version: "0.2"
+# + new promise `runtime.dynamic-modules`
```

## Alternatives rejected

- **Recompile nginx with `--with-stream` baked in** (non-dynamic): nginx from Debian apt is already the right binary; we'd be rebuilding to drop one `.so` file. Not worth custom-nginx-build toolchain.
- **Symlink instead of adding `mime.types`**: there's no systemwide mime.types to symlink to in scratch — it only exists because `nginx` package ships it at `/etc/nginx/mime.types`.
- **Make `/var/run` writable in the image**: creates a bigger writable surface. Standard scratch convention is `/tmp` (1777 from baseline) + per-service pre-created dirs for persistent state (`/var/log/nginx`, `/var/cache/nginx`). sni-router's `pid` is ephemeral — `/tmp/nginx.pid` is the right place.
- **Rename `www-data` to `nginx` (match sni-router's current)**: Debian owns `www-data` as the nginx uid 33 convention. Consumers conform; baked uid changes would break other overlays.

## Breaking changes

None. Existing consumers see:
- image size +205 KB
- zero config-behavior change (default nginx.conf doesn't `load_module`)
- mime.types is additive (consumers who `include` it now succeed; consumers who don't aren't affected)

## Rollout

- `nginx-scratch-trixie:1.26` republishes on next `build.yml` with the new overlay + 0.2 contract.
- homelab's `sni-router` applies the 3-line adoption diff + deletes `docker/sni-router/Dockerfile` + flips compose to `ghcr.io/bboortz/nginx-scratch-trixie:1.26`.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: modules + mime.types bundled | `smoke_modules_present.sh` + FG-016 acceptance | ✅ |
| Scenario: sni-router config validates | `smoke_stream_config_validates.sh` (homelab-exact shape) | ✅ |
| Scenario: no regression on existing consumers | `smoke_serves_200.sh` (all existing nginx smokes green) | ✅ |
| Semver bump 0.1 → 0.2 accepted | `contracts-semver-check` + FG-016 acceptance | ✅ |
| `make check-strict` green cold cache | local | ⏳ |
