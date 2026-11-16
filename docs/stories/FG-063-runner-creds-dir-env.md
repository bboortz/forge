---
id: FG-063
slug: runner-creds-dir-env
status: ready
owner: bboortz
created: 2026-11-16
---

# FG-063 — `github-runner-noble` entrypoint gains `RUNNER_CREDS_DIR` env var

Homelab (`bb-claw/homelab`) hit a "binary shadow" bug on `github-runner-noble`: the compose service mounted a named volume at `/home/runner` for credential persistence, but Docker only seeds a named volume **once** on first start — so every subsequent `docker compose up --pull always` kept the stale runner binary from the first-seed, silently ignoring every new forge image bump. Workaround was manual: `docker volume rm github-runner_github-runner-data && systemctl restart github-runner.service`.

Homelab PR #229 proposed the fix client-side: bind-mount a wrapper `runner-entrypoint.sh` into the container that symlinks `/home/runner/.runner` + `/home/runner/.credentials` to a narrower `/runner-creds` volume. That fixes the symptom but:

- **Two repos now share responsibility for the same lifecycle decision.** Any change to the forge entrypoint (new signal handling, cleanup logic) silently diverges from the wrapper.
- **The consumer has to supply the wrapper script + override `entrypoint:` in compose** — fragile.

FG-063 moves the fix into the single place that owns the runner lifecycle: the forge image's `/entrypoint.sh`. The entrypoint reads a new `RUNNER_CREDS_DIR` env var. When set to something other than the default `/home/runner`, it ensures the credential files (`/home/runner/.runner`, `/home/runner/.credentials`, `/home/runner/.credentials_rsaparams`) are symlinks into `${RUNNER_CREDS_DIR}` BEFORE invoking `config.sh` / `run.sh`. Consumers (homelab) only add the volume + set the env var — no wrapper, no bind mount, no entrypoint override.

## 9 canonical answers

1. **Who** — Homelab (today); any future forge consumer that wants to persist runner credentials without shadowing the binary. Also the forge maintainer who now owns the credential-path indirection in one place.

2. **When** — Fires on every `docker compose up` (or Kubernetes Deployment) that sets `RUNNER_CREDS_DIR` and mounts a narrow volume at that path. Transparent to anyone who does NOT set the env var (default preserves today's single-volume behavior).

3. **What success looks like**:
   - Set `RUNNER_CREDS_DIR=/runner-creds` + mount a volume at `/runner-creds` → entrypoint symlinks `.runner` + `.credentials` + `.credentials_rsaparams` from `/home/runner/` into `/runner-creds/`. First start writes through the (dangling) symlinks; subsequent starts resolve them and skip registration. Binary updates in new forge image layers land immediately.
   - Unset / set to `/home/runner` → no symlinks are created; today's behavior is preserved exactly.
   - Homelab's follow-up can drop its wrapper script + entrypoint override.

4. **Urgency** — Quality-of-life for consumers. Homelab is actively blocked on cleanly tracking forge image bumps on the runner; the workaround in PR #229 is viable but fragile. Not security-critical.

5. **Happy path**:
   1. Branch `feat/FG-063-runner-creds-dir-env` from `dev`.
   2. Teach `images/github-runner-noble/entrypoint.sh` to read `RUNNER_CREDS_DIR` (default `/home/runner`). When non-default, `mkdir -p` the target + `ln -sf` three credential files into it.
   3. New smoke `images/github-runner-noble/tests/smoke_runner_creds_dir.sh` — proves default path is a no-op and a non-default path produces the three symlinks before config.sh runs.
   4. Bump `images/github-runner-noble/PROMISES.yaml` 0.1 → 0.2 + add `runtime.runner-creds-dir-env` promise.
   5. NEW CAP `image.github-runner-creds-dir` + extend `image.github-runner-noble-pre-baked`.
   6. Red acceptance test `tests/acceptance/test_FG_063_runner-creds-dir-env.sh`.
   7. CI full-check → auto-merge → next cron republishes with the new entrypoint.
   8. Homelab follow-up PR removes wrapper, drops `entrypoint:` override, keeps only `RUNNER_CREDS_DIR` + narrow volume.

6. **Edge cases / failure modes**:
   - **First-start with empty `RUNNER_CREDS_DIR`**: symlinks are dangling → `config.sh` writes through them → credentials land in `RUNNER_CREDS_DIR`. ✓
   - **Restart with populated `RUNNER_CREDS_DIR`**: symlinks resolve → entrypoint sees `.runner` exists → skips `config.sh` → `run.sh` starts against the latest binary from the image. ✓
   - **`RUNNER_CREDS_DIR=/home/runner` (default)**: the symlink step is skipped entirely so we don't `ln -sf /home/runner/.runner /home/runner/.runner` and introduce a self-loop. ✓
   - **`RUNNER_CREDS_DIR` dir doesn't exist**: `mkdir -p` creates it. The volume mount writes through on first start.
   - **`RUNNER_CREDS_DIR` has stale files from a previous runner version**: out of scope — if credentials are still valid, they continue to work; if the runner org/token rotated, the `.runner` exists and `run.sh` fails loudly like it does today. Not FG-063's problem.
   - **GHE Server deploys using RSA params**: `.credentials_rsaparams` gets symlinked too, so RSA-auth deploys work unchanged.

7. **Out of scope**:
   - Any homelab-side change. That lands in a separate homelab PR after this ships.
   - Changing the default. `/home/runner` stays default; opt-in via env var only.
   - Multi-runner-per-image, runner cleanup on shutdown, PAT rotation flows.

8. **How we know it's done** — see Gherkin.

9. **Capabilities delivered or extended**:
   - NEW `image.github-runner-creds-dir` — entrypoint accepts a `RUNNER_CREDS_DIR` env var that redirects credential persistence to an operator-chosen path via symlinks, so the runner binary stays in the image layer.
   - EXT `image.github-runner-noble-pre-baked` — now carries the credential-path indirection.

## Gherkin acceptance

```
Scenario: default RUNNER_CREDS_DIR is a no-op
  Given github-runner-noble:latest with RUNNER_CREDS_DIR unset (or =/home/runner)
  And no .runner file in /home/runner (fresh container)
  When entrypoint runs with GITHUB_ORG unset
  Then entrypoint exits nonzero with "GITHUB_ORG env var is not set"
  And no symlinks were created in /home/runner (behavior identical to pre-FG-063)

Scenario: non-default RUNNER_CREDS_DIR creates three symlinks
  Given github-runner-noble:latest with RUNNER_CREDS_DIR=/runner-creds
  And /runner-creds is an empty mounted dir
  And no .runner anywhere
  When entrypoint runs with GITHUB_ORG unset (to short-circuit before config.sh)
  Then entrypoint exits nonzero with the usual missing-GITHUB_ORG error
  And /home/runner/.runner is a symlink → /runner-creds/.runner
  And /home/runner/.credentials is a symlink → /runner-creds/.credentials
  And /home/runner/.credentials_rsaparams is a symlink → /runner-creds/.credentials_rsaparams

Scenario: pre-populated RUNNER_CREDS_DIR short-circuits config.sh
  Given github-runner-noble:latest with RUNNER_CREDS_DIR=/runner-creds
  And /runner-creds/.runner exists (operator mounted a pre-registered volume)
  When entrypoint runs (with any GITHUB_ORG, since it should be ignored)
  Then entrypoint reports "Runner already registered (/home/runner/.runner exists), skipping config.sh"
  And entrypoint attempts to exec /home/runner/run.sh

Scenario: binary updates propagate without manual volume flush
  Given a container previously started with RUNNER_CREDS_DIR=/runner-creds
  When a new forge image layer is pulled and the container restarts
  Then /home/runner/bin/Runner.Listener is the NEW version (from the fresh image layer)
  And /runner-creds/.runner is the OLD credential (reused)

Scenario: Dockerfile still ENTRYPOINT=/entrypoint.sh
  Given images/github-runner-noble/Dockerfile at HEAD
  Then ENTRYPOINT points at /entrypoint.sh (consumer contract unchanged)
```

## References

- Plan: `docs/plan/FG-063-runner-creds-dir-env-plan.md`
- Red test: `tests/acceptance/test_FG_063_runner-creds-dir-env.sh`
- Capabilities: `docs/CAPABILITIES.md`
- Driving homelab PR: https://github.com/bb-claw/homelab/pull/229 (will be replaced by a follow-up PR after this ships).
