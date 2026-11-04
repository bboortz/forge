---
id: FG-009
slug: python-scratch-hardening
status: shipped
owner: bboortz
created: 2026-11-04
---

# FG-009 — python-scratch hardening + SSL fix for every scratch derivative

Addresses Beaconry's feedback on the current `python-scratch-trixie` image:

1. **Blocking**: HTTPS is broken out of the box. The baseline ships `/etc/ssl/certs/ca-certificates.crt` and sets `ENV SSL_CERT_FILE` — but baseline ENVs don't flow through `COPY --from=scratch_base`. Every derivative silently loses the env; `urllib.request.urlopen('https://...')` fails with `CERTIFICATE_VERIFY_FAILED`. This affects **every** scratch derivative (python, nginx, postgres), not just python. Fix by re-declaring `ENV SSL_CERT_FILE` + `SSL_CERT_DIR` in each derivative Dockerfile.
2. Python-scratch **defaults to root**: `.Config.User` empty, every `pip install` or exec runs privileged by default. Fix: `USER 65532:65532` (the nonroot identity FG-008 added to the baseline).
3. Python-scratch has **no `ENTRYPOINT`** — `docker run <image> script.py` doesn't invoke python at all. Fix: `ENTRYPOINT ["/usr/local/bin/python3"]`, `CMD []`. Distroless convention.
4. **PYTHONDONTWRITEBYTECODE + PYTHONFAULTHANDLER** absent: `.pyc` written on read-only rootfs crashes; segfaults give no traceback. Fix: bake these ENVs.

Memory-file update: `memory/scratch-closures.md` gains the ENV-doesn't-propagate warning in bold — it's the most consequential trap we've hit. The baseline-contract doc already references it; the closures note links to the contract.

Depends on FG-008 (`scratch-base-trixie:0.2` provides the nonroot identity + /nonroot home dir).

## 9 canonical answers

1. **Who** — Beaconry, who hit all four issues in production use. Any consumer whose Python code does HTTPS, uses pwd.getpwuid, or relies on docker-ecosystem conventions (`docker run <image> script.py`).
2. **When** — on every PR / pre-push / daily cron. The ENV fix is a one-line Dockerfile change per variant.
3. **What success looks like** —
   - `docker run ghcr.io/bboortz/python-scratch-trixie:3.13 -c "import urllib.request; print(urllib.request.urlopen('https://example.com').status)"` prints `200` out of the box
   - `docker inspect .../python-scratch-trixie:3.13 --format='{{.Config.User}}'` is `65532:65532`
   - `docker run <image> -c "print('ok')"` works (ENTRYPOINT=python3)
   - `docker inspect .../python-scratch-trixie:3.13 --format='{{.Config.Env}}'` contains `SSL_CERT_FILE`, `SSL_CERT_DIR`, `PYTHONDONTWRITEBYTECODE=1`, `PYTHONFAULTHANDLER=1`
   - Same SSL_CERT_FILE env set on nginx-scratch + postgres-scratch so their outbound TLS (nginx proxy_pass SSL verification, postgres_fdw remote-connect, grype DB download in consumer builds) also works
4. **Urgency** — product tier, blocking for Beaconry's rollout. The SSL fix in particular can't wait.
5. **Happy path** —
   1. `python-scratch-trixie/Dockerfile`: ENV SSL_CERT_FILE + SSL_CERT_DIR + PYTHONDONTWRITEBYTECODE=1 + PYTHONFAULTHANDLER=1; ENTRYPOINT ["python3"] + CMD []; USER 65532:65532; WORKDIR /nonroot.
   2. `nginx-scratch-trixie/Dockerfile`: ENV SSL_CERT_FILE + SSL_CERT_DIR.
   3. `postgres-scratch-trixie/Dockerfile`: same SSL ENVs.
   4. Replace `smoke_tls_handshake.sh` (lazy context creation, fooled us) with `smoke_tls_https_real.sh` (actual `urlopen` returning 200). This is the test gap that slipped FG-008 past silent-SSL-failure.
   5. New smoke: `smoke_user_nonroot.sh` — inspect + runtime verification that image runs as 65532 with HOME=/nonroot.
   6. Rewrite `smoke_entrypoint.sh` for the new ENTRYPOINT=python3 convention: `docker run <image> -c "..."` just works.
   7. Update smoke_imports / smoke_ca_bundle / smoke_pip_runtime_install to use `--entrypoint=python3` (explicit override — survives any future ENTRYPOINT change AND works for the slim variant too, where CMD=["python3"] replaced ENTRYPOINT invocation was less robust).
   8. `memory/scratch-closures.md` adds a bold warning about the ENV-propagation trap. Links to `docs/baseline-contract.md`.
6. **Edge cases / failure modes** —
   - Consumers who relied on root for `pip install` into system site-packages: have to either add `USER root` back explicitly OR use `pip install --target /tmp/pkg` (which /nonroot and /tmp both allow). Migration cost acknowledged.
   - Consumers who ran `docker run <image> pip install ...`: now needs `docker run --entrypoint=pip <image> install ...` or `docker run <image> -m pip install ...`.
   - Containers that need to bind to privileged ports (<1024): `USER 65532` can't — they add `USER root` + `CAP_NET_BIND_SERVICE` as before.
   - PYTHONFAULTHANDLER adds a tiny runtime overhead on crash (writes traceback to stderr). Negligible.
7. **Out of scope** — a separate `:3.13-nonroot` tag (just make the whole image nonroot per user's "follow defaults" answer); nginx/postgres USER changes (they already set their own service users); applying the ENV fix to a future `python-slim-trixie` (slim keeps its current shape since baseline isn't a dependency).
8. **How we know it's done** — see Gherkin + FG-009 acceptance test.
9. **Capabilities** —
   - EXT `test.image-smoke-suite` — python-scratch gains `smoke_tls_https_real` + `smoke_user_nonroot`; old lazy `smoke_tls_handshake` retired
   - EXT `test.scratch-contents` — nothing new, documented for audit trail
   - NEW `image.ssl-cert-env` — convention: every Forge scratch derivative re-declares `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`
   - NEW `image.python-scratch-nonroot` — python-scratch-trixie defaults to USER 65532, WORKDIR /nonroot, ENTRYPOINT ["python3"]

## Gherkin acceptance

```
Scenario: python-scratch does real HTTPS out of the box
  Given docker run --rm ghcr.io/bboortz/python-scratch-trixie:3.13 \
          -c "import urllib.request; print(urllib.request.urlopen('https://example.com').status)"
  Then the output is "200"

Scenario: python-scratch runs as nonroot by default
  Given the published image
  Then docker inspect reports .Config.User = "65532:65532"
   And docker run reports os.geteuid() == 65532
   And docker run reports pwd.getpwuid(65532).pw_dir == "/nonroot"

Scenario: python-scratch ENTRYPOINT is python3
  Given docker run --rm <image> -c "print('ok')"
  Then stdout is "ok"
   And docker inspect .Config.Entrypoint = ["/usr/local/bin/python3"]

Scenario: python-scratch Env contains the Beaconry-requested vars
  Given docker inspect .Config.Env
  Then it contains SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
   And SSL_CERT_DIR=/etc/ssl/certs
   And PYTHONDONTWRITEBYTECODE=1
   And PYTHONFAULTHANDLER=1

Scenario: every scratch derivative re-declares SSL_CERT_FILE
  Given the three scratch Dockerfiles (python/nginx/postgres)
  Then each contains an ENV line setting SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

Scenario: scratch-closures.md documents the ENV-doesn't-propagate trap
  Given memory/scratch-closures.md
  Then it contains a section flagging that baseline ENVs don't flow through COPY --from=scratch_base
```

## References

- Plan: [`docs/plan/FG-009-python-scratch-hardening-plan.md`](../plan/FG-009-python-scratch-hardening-plan.md)
- Red test: [`tests/acceptance/test_FG_009_python-scratch-hardening.sh`](../../tests/acceptance/test_FG_009_python-scratch-hardening.sh)
- Capabilities: [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
- Memory: [`memory/scratch-closures.md`](../../memory/scratch-closures.md)
