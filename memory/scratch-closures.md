*Hard-won lessons from engineering `FROM scratch` runtimes across python, nginx, postgres, and the shared `scratch-base-trixie` baseline (FG-003, FG-006, FG-007, FG-005). Consult before adding any new scratch image.*

## The baseline + overlay composition

Every Forge scratch image is literally `FROM scratch` and composes by:

```dockerfile
ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
FROM ${SCRATCH_BASE_REF} AS scratch_base

FROM <builder-base> AS builder
# ...assemble image-specific overlay into /out...

FROM scratch AS runtime
# hadolint ignore=DL3067
COPY --from=scratch_base / /     # baseline first
COPY --from=builder /out /       # image overlay — later COPY wins

# MANDATORY — see § "ENV does not propagate" below.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
```

## **⚠️ ENV does not propagate through `COPY --from=`** (FG-009 lesson)

`COPY --from=scratch_base / /` copies **files only** — not the baseline's `ENV` directives. Every scratch derivative **must re-declare** every shared env var in its own Dockerfile, including:

- `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` (TLS verify path; without this, urllib / requests / pip / cosign all fail with `CERTIFICATE_VERIFY_FAILED` — hit by Beaconry in production)
- `SSL_CERT_DIR=/etc/ssl/certs`

This is the single highest-impact trap of the composition pattern. It passed our FG-005 smoke suite because `smoke_tls_handshake.sh` only called `ssl.create_default_context()` (lazy — doesn't touch the trust store). Replaced in FG-009 with `smoke_tls_https_real.sh` doing an actual `urlopen('https://example.com')`. Future scratch image additions MUST include a real-HTTPS smoke to catch this regression.

Baseline supplies: ld-linux + core glibc (**NOT libutil**) + TLS + DNS + `libz` + `libzstd` + CA bundle + `/etc/nsswitch.conf` + `/etc/passwd`+`/etc/group` (root + nobody) + `/usr/share/zoneinfo`. Everything else is image-specific.

Derivatives declare `depends_on: [scratch-base-trixie]` in `image.yaml` so `scripts/build-image.sh` auto-chains baseline → derivative on a cold cache.

## Rules the hard way

### Strict intersection — if one variant doesn't need it, it's not baseline

`libutil.so.1` was in the first baseline draft. nginx's `ldd` closure doesn't include it. python + postgres use it (pty/openpty, forkpty). Removed from baseline; each needing image adds it in its overlay. The 24 KB saved is incidental — **the principle is what makes the baseline predictable**. Every future baseline addition must be a measured ldd/strace intersection across every existing derivative.

### `/etc/passwd` + `/etc/group`: append, never overwrite

Baseline ships root + nobody. Derivatives that need a service user (nginx www-data at 33, postgres postgres at 999) pull baseline's identity files into the **builder** stage via `COPY --from=scratch_base /etc/passwd /tmp/baseline-passwd`, cat them, append their service-user line, and write the merged file to `/out/etc/`. The final `COPY --from=builder /out /` in the runtime stage carries the merged file forward. Overwrite-style (ignoring baseline's content and writing your own full passwd) worked but silently dropped future baseline additions on rebuild. Append-style is the convention.

### Pin service UIDs to the ecosystem convention, not whatever apt assigns

Debian's `postgresql-17` package assigned postgres uid dynamically (we saw **100**); Docker Hub's official `postgres:17` uses **999**. A cluster data directory `initdb`'d by uid 999 is EACCES-rejected by a uid-100 server. Hard-code 999 in the Dockerfile. Same principle applies to any future image whose data dir is shared with the broader ecosystem (nginx www-data **33**, redis would be **999**, etc.).

### `cp` vs `cp -a` and symlink dereferencing

`/lib64/ld-linux-x86-64.so.2` is a Debian multiarch symlink pointing at `../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`. `cp -a` preserves the symlink; `cp` dereferences. python-scratch's Dockerfile uses plain `cp`; nginx-scratch originally used `cp -a` — the resulting image shipped a dangling symlink and the binary failed to exec with "No such file or directory" (ENOENT on the interpreter). **Use plain `cp` for dyn-linker + libs so SONAME paths are real files**. Python stdlib / interpreter uses `cp -a` deliberately because it contains valid relative symlinks inside a single tree.

### Upstream tools that LOOK like ELF but are actually shell-script wrappers (FG-043 homelab lesson 2026-11-10)

`file /usr/sbin/<tool>` lies by habit — Debian packages routinely ship 300-500 byte `#!/bin/sh` wrappers that set default flags and `exec` a real ELF binary. Catalogued so far:

- `/usr/sbin/ipmimonitoring` (freeipmi-tools) — wraps `ipmi-sensors` with `--output-sensor-state --ignore-not-available-sensors`
- `/usr/sbin/ipmi-chassis-config`, `ipmi-pef-config`, `ipmi-sensors-config` (freeipmi-tools)
- `/usr/sbin/update-ca-certificates` (ca-certificates) — shell
- Many `*-config` scripts under `/usr/bin/` from `*-dev` packages

**FG-043 hit this**: prometheus-ipmi-exporter's `ipmi` collector defaults to invoking `ipmimonitoring`. I shipped the 5 ELF binaries (`ipmi-sensors` etc.) but NOT `ipmimonitoring` + `/bin/sh`. Container booted fine. CI smokes passed (they only check `--version` + `/metrics` responds). But on real hardware with `/dev/ipmi0`: `ipmi_up{collector="ipmi"}=0` and zero sensor readings because the wrapper exec failed with ENOENT. The sibling slim variant worked on the same host — masking the regression completely from any CI-only testing.

**Fixes that work** (in order of elegance):

1. **If the wrapper's logic is just "add fixed flags"** — use the upstream exporter's own config to call the real ELF binary with those flags. For prometheus-ipmi-exporter: `collector_cmd.<name>: <real-binary>` + `custom_args.<name>: [...wrapper-flags]` in `ipmi-exporter.yml`.
2. **If the wrapper has conditional logic** — reimplement it as a static Go/Zig binary (same shape as `/hc`) and name it `<wrapper>`. Scratch-safe.
3. **Last resort** — ship a static `/bin/sh` from busybox + the wrapper. Breaks the no-shell contract; needs explicit documentation.

**Smoke pattern to catch this class of bug** (FG-043's `smoke_ipmi_collector_uses_elf.sh`):

```bash
# Run container without the device/hardware it needs. Trigger a scrape.
# Wait for logs to flush. Grep for "<wrapper>: executable file not found"
# in stderr. If the pattern appears, the upstream tool is calling a
# missing shell wrapper and the image will silently fail on real hardware.
```

This is the ONLY smoke shape that would have caught FG-043's regression — every file-presence / `--version` / `/metrics-returns-200` check passed clean.

Signals that a Debian tool is a wrapper (check BEFORE assuming it's shippable in scratch):
- File size: ELF binaries for IPMI/network tools are typically **>100 KB**. A 300-500 byte "binary" is almost certainly a shell script.
- `head -1 <path>` → if first two bytes are `#!`, it's a script.
- `ldd <path>` on a static shell script: `not a dynamic executable` (same as a static ELF — distinguish by file size).
- `apt-file list <pkg>` → if the package depends on another `-common` package shipping `/etc/<pkg>/*.conf`, those config files are typically needed at runtime too (freeipmi-common's `/etc/freeipmi/*.conf` was the other FG-043 oversight).

### Scratch has no shell — anything using `system()` won't work in-container

Postgres' `initdb` internally calls `system()` to run `postgres -V` for compatibility checking. `system()` → `/bin/sh -c ...` → ENOENT on `/bin/sh` → initdb reports a cryptic "postgres was not found in the same directory as initdb". **Scratch images cannot run workflows that invoke a shell**, even transitively. Workaround: a **shelled sidecar** for one-time init (postgres:17 or a future slim variant), then the scratch runtime for serving. Documented in FG-007 as the `test.sidecar-init` pattern. Run the server-use-case smoke tests via that pattern; don't try to initdb in-scratch.

### Default service configs usually need adaptation for scratch

- nginx default `nginx.conf` includes `conf.d/`, `sites-enabled/`, and `modules-enabled/` + requires `/var/cache/nginx` and `/var/lib/nginx/{body,fastcgi,proxy,scgi,uwsgi}` dirs. Ship a minimal self-contained config and pre-create the writable dirs with correct chown.
- postgres default `pg_hba.conf` only allows 127.0.0.1/32; cross-container traffic over the docker bridge needs `host all all 0.0.0.0/0 trust` appended for testing.
- nginx compiles with `--user=nobody --group=nogroup` as the default; our `/etc/group` had no `nogroup`. Fix: explicit `user www-data www-data;` in `nginx.conf`.

### Writable dirs: `/tmp` must be 1777; service dirs need the right chown

Baseline ships `/tmp` with mode 1777. Each image that writes to a service dir (nginx's `/var/log/nginx`, `/var/cache/nginx`, `/var/lib/nginx/*`; postgres' `/var/lib/postgresql`, `/var/run/postgresql`) creates the dir with `install -d` in the builder's RUN then `chown -R <uid>:<gid>`. **No shell at runtime means no post-start `mkdir`** — all writable paths must exist at image build time with correct perms.

## The build / test / publish ordering trap

### Build ordering (local)

Scratch derivatives `FROM ${SCRATCH_BASE_REF}` where `SCRATCH_BASE_REF` defaults to `ghcr.io/bboortz/scratch-base-trixie:latest`. For local dev without a published baseline, `scripts/build-image.sh` reads `depends_on:` from the derivative's `image.yaml` and recursively builds the baseline FIRST into `forge-local/scratch-base-trixie:0.1`, then overrides `SCRATCH_BASE_REF` via `--build-arg` so the derivative resolves locally.

### Legacy docker builder + `--pull` trap

`docker build --pull` on a legacy builder (not buildkit) attempts to pull EVERY `FROM` reference, even when the image is locally present. For `forge-local/...:0.1` references that don't exist in any real registry, the pull fails with "pull access denied" and aborts the whole build. `scripts/build-image.sh` conditionally drops `--pull` when the baseline resolves locally.

### Publish ordering (CI)

`.github/workflows/build.yml` splits into `publish-base` (matrix over images with no `depends_on`) → `publish-derivatives` (matrix with `needs: publish-base`). On a cold runner, the derivative pulls baseline from GHCR; the ordering guarantees baseline is published first. Don't try to encode this in a single matrix.

### Layer-order iteration when inspecting /etc/passwd via `docker save`

`for layer in blobs/sha256/*` iterates **alphabetically**, which doesn't match **layer order**. If the derivative overlay's blob happens to sort before the baseline's blob, extracting `/etc/passwd` from every layer in sorted order makes the baseline overwrite the overlay — so the service user gets lost from the test's view. Walk `manifest.json .Layers[]` in order instead.

## Smoke-test patterns

### `test.scratch-contents` — for images with no exec

Baseline has no binary to run. Validate contents via `docker save` + `tar tf` + path presence/absence checks: `smoke_contents_required_files.sh`, `smoke_contents_no_shell.sh`, `smoke_contents_zero_os_cves.sh`, `smoke_size.sh`. This pattern fits any image whose smoke can be reduced to "the right files are/aren't in the image."

### `test.smoke-server-helper` — for images that boot a daemon

`scripts/smoke-server.sh` encapsulates `docker run -d -p 0:PORT` + resolve host port + poll readiness + run test command + always clean up. Used by nginx (`smoke_serves_200.sh`) and the postgres server smoke. Pattern: start container, substitute `__HOST_PORT__` in the ready/test strings, exit with the test command's RC. Dumps `docker logs` on failure.

### `test.sidecar-init` — for shell-requiring init workflows

Postgres' initdb needs `/bin/sh`. Scratch has none. Pattern: use a shelled sidecar image (Docker Hub's `postgres:17` for the smoke test; could be a future `postgres-slim-trixie`) to initialize state into a named docker volume, then start the scratch runtime against that volume. Smoke test chains `docker run --rm -v vol:/data <shelled-sidecar> initdb ...` → `docker run -d -v vol:/data <scratch> postgres ...` → `docker run --network=host <scratch> psql ...`.

### Capture docker-run output on failure

`set -e` inside `out=$(docker run ... 2>&1)` kills the smoke script before the output can print. Pattern:

```bash
set +e
out=$(docker run --rm "${IMAGE}" <cmd> 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "  ✗ exited ${rc}:" >&2
  echo "${out}" >&2
  exit 1
fi
```

PR #9 CI failed mysteriously ("Error 1" with no diagnostic) exactly because this pattern wasn't applied.

### hadolint ignore directives must be *directly* above the instruction

A `# hadolint ignore=DL3067` with one or more comment lines between it and the `COPY` line is silently ignored by hadolint. Put the explanation ABOVE the ignore directive; put the directive immediately above the instruction.

## CI environment ≠ local environment

Two memorable PR failures that pre-push `make check` didn't catch because they depended on CI-only state:

1. **ci.yml job-level `env:` leak** (PR #9, FG-006) — a leftover `env: { IMAGE_NAME: python, IMAGE_TAG: 3.13-slim-trixie }` from pre-FG-004 injected those values into every test step, including FG-006's smoke scripts, which then tried to `docker run forge-local/python:3.13-slim-trixie` (no longer exists). Local shell doesn't inject job-scoped env.
2. **stale docker image cache** (PR #7, FG-004) — an old `forge-local/python:3.13-slim-trixie` image from a pre-FG-004 session was cached on the workstation; `test_FG_002`'s stale `IMAGE_REPO=python` picked it up and passed; CI runner is always cold and failed.

Mitigation: `make clean-local-images` wipes every `forge-local/*` image; pre-push gate uses `check-strict` which runs `clean-local-images` before `check`. **Doesn't catch GHA env injection** — some CI classes of failure can only be caught on a clean runner.
