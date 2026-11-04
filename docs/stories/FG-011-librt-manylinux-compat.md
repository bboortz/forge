---
id: FG-011
slug: librt-manylinux-compat
status: shipped
owner: bboortz
created: 2026-11-04
---

# FG-011 — librt.so.1 ABI stub for manylinux2014 wheel compatibility

Ship `librt.so.1` (14.5 KB empty ABI stub, as shipped by Debian trixie) in `python-scratch-trixie` so manylinux2014 / manylinux_2_17 wheels — including numpy, scipy, pandas, pillow, cryptography — dlopen successfully.

glibc 2.34 (Aug 2021) merged librt into `libc.so.6`. The baseline doesn't need librt. Python itself doesn't need librt. But every binary wheel built against `manylinux2014` (PEP 599) or `manylinux_2_17` targets **glibc 2.17** (CentOS 7 era), which predates the merge. Those wheels carry `NEEDED librt.so.1` in their ELF dynamic section; the loader then looks for `librt.so.1` at import time. Without the stub, `pip install numpy` + `import numpy` fails in the scratch container.

Scope: python-scratch-trixie only. Not the baseline — this is a Python-ecosystem concern, not a universal glibc requirement. nginx and postgres aren't affected.

## 9 canonical answers

1. **Who** — any consumer who `pip install`s a popular binary wheel into python-scratch-trixie. Beaconry flagged it.
2. **When** — on every PR / pre-push / daily cron. The fix is a one-word Dockerfile change + a new smoke.
3. **What success looks like** —
   - `/lib/x86_64-linux-gnu/librt.so.1` is present in the published image (14.5 KB stub).
   - `docker run --entrypoint=python3 ghcr.io/bboortz/python-scratch-trixie:3.13 -c "import ctypes; ctypes.CDLL('librt.so.1')"` prints no error and exits 0.
   - A wheel with `NEEDED librt.so.1` installs and imports without dlopen failure.
   - A new preflight expectation on python-scratch-trixie covers the contract via `smoke_librt_manylinux.sh`.
4. **Urgency** — product tier. Consumer-facing silent failures when installing wheels. Not security-critical by itself.
5. **Happy path** —
   1. `images/python-scratch-trixie/Dockerfile`: add `librt.so.1` to the lib COPY loop.
   2. `images/python-scratch-trixie/tests/smoke_librt_manylinux.sh`: verify file present in layers + `ctypes.CDLL('librt.so.1')` succeeds at runtime.
   3. Extend `images/python-scratch-trixie/PROMISES.yaml`: new promise `runtime.librt-abi-stub` linked to the smoke. Bump image version 0.1 → 0.2 (semver-gated minor bump — added a promise).
   4. CAP: new `image.manylinux-wheel-compat`.
   5. FG-011 acceptance test encodes the Gherkin.
   6. Memory: scratch-closures gains a short note on the manylinux2014 + librt trap.
6. **Edge cases / failure modes** —
   - Debian removes the librt stub entirely (future) — baseline refresh or sid-pin would break the COPY. Dockerfile uses `|| true` tolerance; the smoke would fail loudly and prompt re-evaluation.
   - A consumer `apt-upgrade`s inside a derived builder stage and picks up a non-stub librt — benign; still dlopen-able.
   - arm64 build (future): librt.so.1 lives at `/lib/aarch64-linux-gnu/librt.so.1`; same logic applies. Out of scope for V1 (amd64-only).
7. **Out of scope** —
   - Adding librt to the baseline. It's a Python-ecosystem artefact; nginx/postgres don't carry pre-2021 wheels.
   - Adding every manylinux_2_17-expected lib defensively. Only librt is the known gap; `pip install --target` of any popular wheel already works if its .so has only standard libc NEEDED entries.
   - Running a representative wheel install (e.g. `pip install numpy`) in the preflight — that's a 20 MB network fetch at every CI tick. `ctypes.CDLL` is the mechanical check at the layer that actually fails.
8. **How we know it's done** — Gherkin + FG-011 acceptance test green; published image passes `ctypes.CDLL('librt.so.1')`.
9. **Capabilities** —
   - NEW `image.manylinux-wheel-compat` — python-scratch-trixie ships the librt ABI stub so manylinux2014/_2_17 wheels dlopen successfully
   - EXT `image.python-scratch-nonroot` — the python-scratch guarantee set grows by one promise
   - EXT `contracts.promises` — the new promise is declared + semver-bumped (0.1 → 0.2)

## Gherkin acceptance

```
Scenario: librt.so.1 stub ships in python-scratch-trixie
  Given the published image
  When I inspect its filesystem
  Then /lib/x86_64-linux-gnu/librt.so.1 is present

Scenario: librt.so.1 is dlopen-able at runtime
  Given a running python-scratch-trixie container
  When I call ctypes.CDLL('librt.so.1')
  Then the call succeeds (no OSError)

Scenario: contract reflects the new guarantee
  Given images/python-scratch-trixie/PROMISES.yaml
  Then it contains promise runtime.librt-abi-stub linked to smoke_librt_manylinux.sh
   And its version: field is at least 0.2 (minor bump from 0.1)

Scenario: verify-contracts stays green with the new promise
  Given the new PROMISES entry
  When `make verify-contracts` runs
  Then it exits 0

Scenario: semver gate accepts the version bump
  Given old PROMISES @ 0.1 vs new @ 0.2 with the added promise
  When `scripts/contracts-semver-check.py --compare old new`
  Then it exits 0 (bump matches add class)
```

## References

- Plan: [`docs/plan/FG-011-librt-manylinux-compat-plan.md`](../plan/FG-011-librt-manylinux-compat-plan.md)
- Red test: [`tests/acceptance/test_FG_011_librt-manylinux-compat.sh`](../../tests/acceptance/test_FG_011_librt-manylinux-compat.sh)
- Smoke: [`images/python-scratch-trixie/tests/smoke_librt_manylinux.sh`](../../images/python-scratch-trixie/tests/smoke_librt_manylinux.sh)
- Capabilities: [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
