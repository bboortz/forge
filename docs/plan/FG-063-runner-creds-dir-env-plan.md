---
id: FG-063
slug: runner-creds-dir-env
story: ../stories/FG-063-runner-creds-dir-env.md
---

# FG-063 plan — `github-runner-noble` entrypoint gains `RUNNER_CREDS_DIR` env var

Story: [FG-063](../stories/FG-063-runner-creds-dir-env.md).

## Design delta

One file does the work: `images/github-runner-noble/entrypoint.sh`.

At the top of the script, after the `set -euo pipefail` line and before the existing `GITHUB_ORG` check:

```bash
RUNNER_DIR="/home/runner"
RUNNER_CREDS_DIR="${RUNNER_CREDS_DIR:-$RUNNER_DIR}"

if [[ "${RUNNER_CREDS_DIR}" != "${RUNNER_DIR}" ]]; then
  mkdir -p "${RUNNER_CREDS_DIR}"
  for f in .runner .credentials .credentials_rsaparams; do
    ln -sf "${RUNNER_CREDS_DIR}/${f}" "${RUNNER_DIR}/${f}"
  done
fi
```

`REG_FILE="${RUNNER_DIR}/.runner"` continues to work unchanged — when `RUNNER_CREDS_DIR` is non-default, `.runner` under `/home/runner` is a symlink that resolves to `${RUNNER_CREDS_DIR}/.runner`; the existing `[[ -f "${REG_FILE}" ]]` check follows the symlink.

Why `ln -sf` (force) not plain `ln -s`: the image layer ships an empty `/home/runner/` (the runner binary lives under `/home/runner/bin/` + `/home/runner/externals/`; the credential dotfiles don't exist until first-start config). Re-runs with populated `${RUNNER_CREDS_DIR}` need the symlinks replaced in case the dotfile was previously created as a regular file (e.g. from a pre-FG-063 image layer still cached on disk).

## Alternatives rejected

- **Make the whole `/home/runner` a symlink to `${RUNNER_CREDS_DIR}`.** Rejected: that re-creates the exact binary-shadow bug (the runner binary tree lives in the image under `/home/runner/bin/` + `/home/runner/externals/` — if `/home/runner` is a symlink into a mounted volume, the volume content wins and masks the binary).
- **Teach the entrypoint to `cp` the credential files into a mounted volume on shutdown.** Rejected: requires a shutdown hook (SIGTERM trap) which is fragile, and Docker named volumes make the symlink approach a strict improvement (first-write lands in the volume with zero copy traffic).
- **Document "do not mount at `/home/runner`" in the README and leave the fix in the consumer.** That's where we are today — homelab PR #229 demonstrates the fragility (two repos share lifecycle responsibility).
- **Add `.path` / `.env` to the symlink set.** Rejected: both are optional runner artifacts and are not persisted in homelab's current deploy. The three that matter are the ones homelab's wrapper already symlinks (`.runner`, `.credentials`, `.credentials_rsaparams`).

## Edit catalogue

### 1. `images/github-runner-noble/entrypoint.sh`

Insert the 7-line `RUNNER_CREDS_DIR` block after `set -euo pipefail`, before the existing `GITHUB_ORG` check. Update the file header comment to mention the new env var.

### 2. `images/github-runner-noble/PROMISES.yaml`

Bump `version: "0.1"` → `"0.2"` (FG-010 semver: new promise added → minor bump). Add:

```yaml
  - id: runtime.runner-creds-dir-env
    description: "/entrypoint.sh reads RUNNER_CREDS_DIR env var (default /home/runner). When set to a non-default path, the entrypoint symlinks .runner, .credentials, .credentials_rsaparams from /home/runner/ into RUNNER_CREDS_DIR before invoking config.sh / run.sh — lets operators persist credentials in a narrow volume without shadowing the runner binary tree."
    caps: [image.github-runner-creds-dir]
    tests:
      - images/github-runner-noble/tests/smoke_runner_creds_dir.sh
```

### 3. `images/github-runner-noble/tests/smoke_runner_creds_dir.sh` (NEW)

Two sub-cases in one script:

- **Default (no env var set)**: run container with `GITHUB_ORG=""` (unset) + `--entrypoint=/entrypoint.sh`. Expect nonzero exit + "GITHUB_ORG env var is not set" in stderr. Expect no symlinks in `/home/runner/` (check with a second `docker run` that inspects the filesystem — since the first container exited).

  Actually simpler: run the entrypoint with `RUNNER_CREDS_DIR` unset + check that no symlinks are created by instrumenting a `bash -c "..."` command.

- **Non-default**: `docker run -e RUNNER_CREDS_DIR=/runner-creds -v /tmp/runner-creds-smoke-TS:/runner-creds -e GITHUB_ORG=""` → entrypoint fails on GITHUB_ORG check, BUT the mkdir + three symlinks must still have happened. Inspect host `/tmp/runner-creds-smoke-TS` → it exists (created by mkdir -p). Then start a second container `docker run --rm --entrypoint=bash ... -c 'readlink /home/runner/.runner'` with the same mount → expect `/runner-creds/.runner`.

### 4. `tests/acceptance/test_FG_063_runner-creds-dir-env.sh` (NEW)

6 sections encoding the 5 Gherkin scenarios + image-build + smoke-suite completion.

### 5. `docs/CAPABILITIES.md`

NEW `image.github-runner-creds-dir`:
```
### image.github-runner-creds-dir

The github-runner-noble entrypoint accepts a RUNNER_CREDS_DIR env var that
redirects credential persistence to an operator-chosen path via symlinks
(/home/runner/.runner, .credentials, .credentials_rsaparams). Default is
/home/runner (backward-compat; no symlinks created). Lets operators persist
runner credentials in a narrow volume without shadowing the runner binary
tree under /home/runner/bin/ + /home/runner/externals/.

- **Delivered by**: FG-063
- **Covered by**: tests/acceptance/test_FG_063_runner-creds-dir-env.sh,
  images/github-runner-noble/tests/smoke_runner_creds_dir.sh
```

Extend `image.github-runner-noble-pre-baked`'s `Extended by:` line.

### 6. `docs/stories/INDEX.md`

Add FG-063 row.

### 7. No change to `Dockerfile`

`ENTRYPOINT ["/entrypoint.sh"]` unchanged. Consumer `docker run`/`compose` config stays the same shape.

## Merge order

1. Branch from `dev`.
2. All edits in one commit.
3. Red test green locally (`FORGE_FAST=0` for full build + smoke).
4. PR → CI full-check → auto-merge.
5. Release workflow fast-forwards main; daily publish (or manual workflow_dispatch) republishes `github-runner-noble:latest` with the updated entrypoint.
6. Homelab follow-up PR (separate repo): drop `runner-entrypoint.sh` + `entrypoint:` override, keep only `RUNNER_CREDS_DIR=/runner-creds` + narrow volume mount.

## Rollout

- Published forge image gains the new env var support at next cron.
- Zero impact on any existing deploy that doesn't set the env var — backward-compat is literal (the whole symlink block is in an `if` gated on the env being non-default).
- Homelab migration: one-line compose env addition after this ships.

## Breaking changes

None. `ENTRYPOINT` shape unchanged. Default behavior preserved by construction.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — default is no-op | Scenario 1 (RUNNER_CREDS_DIR unset → no symlinks) | ⏳ |
| Gherkin — non-default creates 3 symlinks | Scenario 2 | ⏳ |
| Gherkin — pre-populated short-circuits | Scenario 3 | ⏳ |
| Gherkin — binary updates propagate | Scenario 4 (read as: image layer always wins for /home/runner/bin/) | ⏳ |
| Gherkin — ENTRYPOINT unchanged | Scenario 5 | ⏳ |
| Build/scan/verify symmetry | image builds + scans clean + smokes green | ⏳ |
| Self-consistency | CAP added + bidirectional links; PROMISES semver bumped | ⏳ |
| No consumer-contract break | ENTRYPOINT identical; default path unchanged | ⏳ |
