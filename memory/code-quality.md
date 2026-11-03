*Commit, branch, and PR conventions for Forge.*

## Commit message format

```
<type>(<scope>): <description>
```

Types: `feat` `fix` `docs` `refactor` `chore` `ci` `test` `style`

Scopes:
- Image names: `python3.13`, `python3.13-slim`, `nginx-stable`, `postgres-18`, ...
- Pipeline components: `build`, `scan`, `sign`, `verify`, `pins`
- Infra: `ci`, `make`, `docs`

Examples:
- `feat(python3.13): add FROM scratch runtime stage with pinned libxml2 from sid`
- `fix(sign): correct cosign certificate-identity path after workflow rename`
- `chore(pins): remove sid pin for libxml2 — fix backported to trixie`
- `ci(scan): fail PR build on new HIGH/CRITICAL vs. baseline`
- `docs(python3.13): document ldd discovery recipe`

## Branch naming

```
feat/FG-NNN-<slug>     new image or new pipeline capability (plan-doc required)
fix/<slug>             bug fix (clear repro, no plan required for one-line fixes)
docs/<slug>            docs only
refactor/<slug>        no behaviour change in built artifacts
chore/<slug>           tooling, dependency bump, sid-pin add/remove, GHA tweak
```

Every `feat/*` and non-trivial `fix/*` branch needs `docs/plan/<slug>-plan.md`. See `workflow.md`.

## When creating a branch

1. Branch from `dev`, not from `main`
2. Create `docs/plan/<slug>-plan.md` from `docs/plan/_template.md` (feat and non-trivial fix)
3. PR target is **`dev`** — never `main`

## Before creating a PR

Delegate to the gates in `workflow.md`: `make check` must pass locally. Three pre-PR sanity questions still apply:

- Does the Dockerfile actually produce a smaller runtime than the equivalent upstream base? (If not, re-justify the image's existence.)
- Is any `COPY --from=builder` path unused by the entrypoint? (If yes, remove it — the point is minimal.)
- Does any sid pin lack a removal condition in its comment? (If yes, add one — pins without exit conditions calcify.)

PR title: under 70 chars, no trailing period. PR body: Claude writes from branch diff — links plan doc, summary bullets, and includes the grype diff vs. the previous digest.

## Script / shell style

- All shell under `images/<name>/build.sh`, `.github/workflows/*.sh`, and `Makefile` recipes: `shellcheck` clean, `set -euo pipefail` at the top of every script.
- Prefer `make` targets over inline multi-line shell in GHA — easier to run locally, easier to shellcheck.

## Dockerfile style

- `hadolint` must pass. Fix with `hadolint images/<name>/Dockerfile` locally.
- Prefer `ARG` over hard-coded versions for the base image, so a `--build-arg` can override during tests.
- Pin exact digests only in the published image — in-source Dockerfiles use the tag `python:3.13-slim-trixie` and rely on `--pull` for freshness.

## Memory file size limit

`memory/*.md` files ≤ 150 lines. Keep them focused and scannable.
`CLAUDE.md` ≤ 150 lines — @-includes are loaded separately.
