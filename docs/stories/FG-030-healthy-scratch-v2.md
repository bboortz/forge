---
id: FG-030
slug: healthy-scratch-v2
status: shipped
owner: bboortz
created: 2026-11-08
---

# FG-030 — healthy-scratch-trixie v2 (wget → hc)

FG-029 shipped `healthy-scratch-trixie:1` as a wget-based scratch sidecar (24 MB — GnuTLS closure dominates). The size is ~6× larger than `busybox:latest` (~4 MB) that it replaces. User feedback: "not happy with the size and unnecessary tools inside the image."

FG-030 ships `:2` — the same sidecar role, now built around `hc` (a static Zig binary from `bboortz/healthy`, ~400 KB, no libc / heap). The entire GnuTLS stack is gone. Result: **3.5 MB image** (vs. FG-029's 24 MB and busybox's 4.2 MB), finally **smaller than busybox**.

Depends on HC-005 (in the `bboortz/healthy` repo) publishing `ghcr.io/bboortz/hc:0.1.0`. While HC-005 is in flight, this FG uses a local `forge-local/hc:0.1.0` override for build/test.

## 9 canonical answers

1. **Who** — Same consumer set as FG-029: the 4 homelab stacks that run a sleep-forever sidecar to provide a healthcheck tool for a scratch service (`nextcloud/web-hc`, `sni-router/*-hc`, `website/*-hc` ×2). Secondary: any Forge scratch-image consumer who wants minimal attack surface + signed/scanned supply chain for a healthcheck sidecar.

2. **When** — After HC-005 ships. FG-029's `:1` tag remains published but frozen (consumers may continue on `:1` until they migrate). Daily cron picks up the `:2` recipe once FG-030 lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/healthy-scratch-trixie:2` publishes daily with cosign signature + SBOM + scan attestations.
   - Image size ≤ 5 MB (3.5 MB actual).
   - Homelab adopts via `image: ghcr.io/bboortz/healthy-scratch-trixie:2` + rewrites the `healthcheck.test:` line from `["CMD", "wget", "-qO-", "-T", "5", "http://127.0.0.1/healthz"]` to `["CMD", "/hc", "-t", "5", "http://127.0.0.1/healthz"]`.
   - Grype scan stays clean (fewer OS packages than `:1` → smaller CVE surface).

4. **Urgency** — Quality-of-life. Correctness of FG-029's :1 is fine (wget works); FG-030 trades size + attack surface, not correctness.

5. **Happy path**:
   1. HC-005 publishes `ghcr.io/bboortz/hc:0.1.0`.
   2. FG-030 merges; daily cron publishes `:2`.
   3. Homelab stacks bump `image:` and rewrite the `healthcheck.test:` line (flag surface: `wget --timeout=5` → `hc -t 5`; `wget --ca-certificate=X` → `hc --ca X`).
   4. `cosign verify` confirms the new digest.

6. **Edge cases / failure modes**:
   - **HC-005 not shipped yet** — build fails in CI with `FROM ghcr.io/bboortz/hc:0.1.0` resolve error. Guarded by keeping this PR as draft until HC-005 lands. Local devs can `--build-arg HC_REF=forge-local/hc:0.1.0` using a pre-built binary.
   - **hc's flag surface differs from wget** — this is a known breaking change for consumers (healthcheck.test rewrite). Mitigated by sidecar being behind `network_mode:` — operators only interact with it through `HEALTHCHECK` lines, which they rewrite once.
   - **Container needs to stay alive between healthchecks** — hc is one-shot (connect, check, exit). `sleep infinity` is still the container's main process; hc is invoked via docker's healthcheck feature or `docker exec` through the shared netns.
   - **TLS verification differences** — hc never trusts system CAs; always wants `--ca <file>`. wget's `--ca-certificate=` is semantically closest. For healthchecks against private CAs this is a feature; for public CAs (rare in homelab) the consumer must bundle a Mozilla CA file.

7. **Out of scope**:
   - A keepalive mode in hc that removes the need for sleep (future HC-006 could eliminate the 2 MB libc.so.6 overhead — image drops to ~500 KB).
   - Including curl alongside hc — if a consumer needs curl's feature surface they can use `python-slim-trixie` or `postgres-slim-trixie` which both ship curl.
   - Multi-arch (amd64-only, matches every other Forge image).
   - Renaming the image (`healthy-scratch-trixie` stays — same slug, just a new tag).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.healthy-sidecar` — same CAP as FG-029, now with hc instead of wget; CAP description updated to reflect hc as the primary binary.
   - EXT `image.no-shell` — unchanged; still no shell.
   - EXT `scan.sbom-embed` — SBOM shrinks (dropped 11 GnuTLS deps).
   - EXT `test.size-budget` — scratch-image size budget drops from FG-029's 30 MB ceiling to 5 MB.

## Gherkin acceptance

```
Scenario: healthy-scratch-trixie:2 publishes with the standard Forge triple
  Given a successful build.yml publish cycle (after HC-005 publishes hc:0.1.0)
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists coreutils + libc6 (hc has no OS footprint)
   And the grype attestation is attached
   And the OS-CVE count is zero

Scenario: image size is under 5 MB (smaller than busybox)
  Given forge-local/healthy-scratch-trixie:2 is built
  When `docker image inspect --format {{.Size}}` is read
  Then it is ≤ 5_000_000 bytes

Scenario: hc runs and exits with the documented codes
  Given forge-local/healthy-scratch-trixie:2 is built
   And a sidecar container sharing netns with a service listening on :6379
  When `/hc tcp://localhost:6379` runs
  Then it exits 0 (healthy)
  When `/hc tcp://localhost:9999` runs against a closed port
  Then it exits non-zero (unhealthy; stderr reports "ConnectionRefused")

Scenario: default CMD sleeps forever
  Given forge-local/healthy-scratch-trixie:2
  When the container runs with no args
  Then it stays running (no exit within 3s)
   And `docker inspect` reports Cmd = ["/usr/bin/sleep", "infinity"]

Scenario: GnuTLS stack is gone
  Given the built image
  When the runtime file tree is inspected
  Then /usr/bin/wget is absent
   And /lib/x86_64-linux-gnu/libgnutls.so.30 is absent

Scenario: image has no shell
  Given the built image
  When common shell paths are probed via docker run --entrypoint
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh all fail to exec

Scenario: homelab adopts :2 with a 2-line diff per stack
  Given homelab/docker/nextcloud/docker-compose.yml.j2
  When web-hc.image is changed from `ghcr.io/bboortz/healthy-scratch-trixie:1` to `:2`
   And healthcheck.test is rewritten from `[CMD, wget, -qO-, -T, 5, URL]` to `[CMD, /hc, -t, 5, URL]`
  Then docker compose up succeeds
   And the web service's healthcheck via the shared netns turns green
```

## References

- Plan: `docs/plan/FG-030-healthy-scratch-v2-plan.md`
- Red test: `tests/acceptance/test_FG_030_healthy-scratch-v2.sh`
- Capabilities: see `docs/CAPABILITIES.md`
- Upstream: `bboortz/healthy` (HC-005 publishes `ghcr.io/bboortz/hc:0.1.0`)
- Predecessor: FG-029 (`:1`, wget-based, 24 MB)
- Homelab touchpoints (migration): `~/git/homelab/docker/{nextcloud,sni-router,website}/docker-compose.yml.j2` (4 instances)
