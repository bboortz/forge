# FG-006 — Plan: nginx-scratch-trixie

**Story**: [`docs/stories/FG-006-nginx-scratch-trixie.md`](../stories/FG-006-nginx-scratch-trixie.md)
**Status**: shipped (pending post-publish evidence)
**Branch**: `feat/FG-006-nginx-scratch-trixie`

## Design delta

Second scratch image in the Forge catalogue. Two-stage Dockerfile: builder on `python:3.13-slim-trixie` (same base as python-scratch so glibc versions match the ldd closure), runtime `FROM scratch`. Over the python-scratch baseline (glibc, NSS, CA bundle, zoneinfo, /etc/passwd+group, /tmp 1777), FG-006 adds `/usr/sbin/nginx` and four shared-lib additions discovered via `ldd`: `libpcre2-8.so.0`, `libcrypt.so.1` (already in python-scratch), `libz.so.1` (already there), `libzstd.so.1` (already there). Net new vs. python-scratch: nginx binary + libpcre2 + minimal nginx.conf + default html + www-data user.

Introduces `scripts/smoke-server.sh` — a reusable start-wait-probe-stop helper so every future server image (nginx, postgres, redis, …) inherits the same smoke harness instead of reimplementing it.

The nginx config shipped in the image is **deliberately minimal and self-contained**: no `include conf.d/*`, no `include sites-enabled/*`, no `include modules-enabled/*`. Daemon-off, access/error logs to `/dev/stdout`/`/dev/stderr`, pid in `/tmp/nginx.pid`, one `http { server { listen 80; } }` block serving `/usr/share/nginx/html/`. Consumers who want more override the config at runtime with `-v $(pwd)/my.conf:/etc/nginx/nginx.conf`.

## Alternatives rejected

- **Use `nginx:stable-alpine` as the base** — Alpine means musl libc and apk packages; diverges from Forge's Debian+glibc differentiator. Non-starter.
- **Keep Debian's full `nginx.conf` + modular includes** — forces us to COPY conf.d/, sites-enabled/, modules-enabled/, and the exact mime.types file. Lots of stuff a consumer will replace anyway. Minimal self-contained config is cleaner and smaller.
- **Ship without `libcrypt` and `libzstd`** — these are listed in `ldd /usr/sbin/nginx` even though many use cases don't need them. Including them costs 200 KB each; removing would cause an obscure failure for consumers who stumble into a feature that uses them.
- **Share a smoke harness as a per-image helper** (copy-paste per image) — shells out to the same docker invocations; doesn't scale past 2 variants. Central helper is right.

## Breaking changes

None. Additive new image. Existing python-slim-trixie + python-scratch-trixie unchanged.

## Merge plan

Fast tier (local `make check-strict` — wipes forge-local/* first so stale image refs can't hide): lint, verify-sid-pins (vacuous), verify-traceability, test-acceptance (all FG tests), test-images (15 smoke scripts now — python-slim 6 + python-scratch 8 + nginx-scratch 6, assuming new scripts/smoke-server.sh counts under scripts not images).

Wait — `scripts/smoke-server.sh` is a helper, lives under `scripts/`, not `images/<name>/tests/`. `make lint` includes it in the shellcheck sweep.

## Rollout plan

Standard: merge to dev → release.yml → build.yml matrix → auto-enrolls nginx-scratch-trixie (per FG-003 `publish.matrix-auto-discovery`). GHCR package `nginx-scratch-trixie` is created on first push; visibility-flip to public is a one-time manual step.

For this autonomous run: only merge to dev. Operator-triggered release + publish happens when the user is ready.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: nginx -v | `images/nginx-scratch-trixie/tests/smoke_binary_runs.sh` | ✅ |
| Scenario: nginx -t validates config | `images/nginx-scratch-trixie/tests/smoke_config_validates.sh` | ✅ |
| Scenario: HTTP 200 on / | `images/nginx-scratch-trixie/tests/smoke_serves_200.sh` + `scripts/smoke-server.sh` | ✅ |
| Scenario: no shell | `images/nginx-scratch-trixie/tests/smoke_no_shell.sh` | ✅ |
| Scenario: zero Debian-source CVEs | `images/nginx-scratch-trixie/tests/smoke_zero_os_cves.sh` | ✅ |
| Scenario: size ≤ 25 MB | `images/nginx-scratch-trixie/tests/smoke_size.sh` (SIZE_CEILING=25_000_000) | ✅ |
| Scenario: smoke-server.sh is reusable | FG-006 acceptance test (section 4) | ✅ |
| CAP `image.nginx-serves-http` | smoke_serves_200.sh + `docs/CAPABILITIES.md` | ✅ |
| CAP `test.smoke-server-helper` | `scripts/smoke-server.sh` + `docs/CAPABILITIES.md` | ✅ |
| EXT `image.no-shell` | smoke_no_shell.sh | ✅ |
| EXT `image.zero-os-cves` | smoke_zero_os_cves.sh | ✅ |
| EXT `test.size-budget` | smoke_size.sh with 25 MB ceiling | ✅ |
| Scenario: cosign verify primary tag (post-publish) | acceptance test PUBLISHED=1 | ⚠️ post-publish |
| Scenario: nginx-scratch-trixie publishes to new GHCR repo (post-publish) | matrix via FG-003 publish.matrix-auto-discovery | ⚠️ post-publish |

Rows flip to ✅ on `make check-strict` green. Post-publish rows wait on operator-triggered release+publish.

**Local measurements**: image size **15.34 MB** (61 % of the 25 MB ceiling); grype reports 19 total matches, **0** from Debian/dpkg sources (all 19 are in `libssl3`/`libcrypto3` pulled transitively from the trixie archive — they live under `linux-kernel`/`java-archive` etc. — not deb). First publish will confirm cosign verify chain against the new `nginx-scratch-trixie` GHCR repo.
