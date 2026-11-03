# Forge — Claude Instructions

Forge builds minimal, continuously patched container base images. Every image is a two-stage build with a `FROM scratch` runtime, rebuilt daily, scanned with grype, and signed with cosign so downstream consumers can verify the digest.

Full product description: `README.md`

@memory/design-decisions.md
@memory/docker-standard.md
@memory/supply-chain.md
@memory/code-quality.md
@memory/workflow.md

---

## Repository layout

```
README.md                — product description, consumer docs, roadmap
Makefile                 — build / scan / sign / push / verify targets
images/                  — one directory per image we publish
  python3.13/
    Dockerfile           — two-stage: trixie builder + FROM scratch runtime
    sid-pins/            — apt-pinning configs for packages pulled from sid
    build.sh             — image-local build driver (invoked by top Makefile)
  python3.13-slim/
  nginx-stable/          — roadmap
  postgres-18/           — roadmap
.github/workflows/
  build.yml              — daily 03:00 UTC cron: build → scan → sign → push
  ci.yml                 — stratified: fast on feat branches, full on dev + PRs
  release.yml            — manual workflow_dispatch: fast-forward main from dev
docs/                    — design notes, image rationale, consumer playbooks
  stories/               — FG-NNN-<slug>.md + INDEX + _template + _9-questions
  plan/                  — per-change plan docs (FG-NNN-<slug>-plan.md) + _template
  CAPABILITIES.md        — capability matrix; bidirectional links to tests
memory/                  — persistent context for Claude sessions
```

---

## Core pipeline

```
Dockerfile (two-stage)
    │
    ├── Stage 1: builder (python:3.13-slim-trixie)
    │     apt-get upgrade + pinned sid packages where needed
    │     install application dependencies
    │
    └── Stage 2: runtime (FROM scratch)
          COPY interpreter + stdlib + libc + libssl + libm + ld-linux
          no shell, no package manager, no dpkg database
    │
    ↓
syft SBOM (CycloneDX)   → attached as OCI annotation
grype scan (JSON)       → attached as OCI annotation
cosign sign (keyless, GHA OIDC) → verifiable against the Forge public key
    │
    ↓
docker push ghcr.io/bboortz/<image>:latest
```

---

## Key tools

| Tool | Role |
|------|------|
| docker buildx | multi-arch build, cache mount, OCI output |
| apt pinning | pull individual packages from Debian `sid` while base stays on `trixie` |
| syft | SBOM generation (CycloneDX JSON) |
| grype | CVE scan against the built image, output attached as attestation |
| cosign | keyless signing + attestation attach / verify |
| GitHub Actions | daily cron + PR CI |
| hadolint | Dockerfile lint |
| shellcheck | shell lint for `build.sh` / scripts under `.github/` |

---

## Image set (initial)

| Image | Build shape |
|-------|-------------|
| `python3.13` | trixie builder + `FROM scratch` runtime (minimal) |
| `python3.13-slim` | published after apt-upgrade; keeps a shell for operators who need one |

Roadmap in `README.md § Roadmap`.

---

## Development process (DD-TGD)

Design-Driven, Test-Guarded Development. Every published digest traces back to the story that motivated it, the plan that scoped it, and the red acceptance test that proves it. Per feature:

0. **Consult `docs/plan/IDEAS.md`** — backlog of ideas we've already discussed. New ideas go in there immediately.
1. Consumer/maintainer story → `docs/stories/FG-NNN-<slug>.md` (9 canonical questions, Gherkin acceptance). Question 9 names the capabilities the story delivers.
2. Branch `feat/FG-NNN-<slug>` + plan doc `docs/plan/FG-NNN-<slug>-plan.md`.
3. Red acceptance test under `tests/acceptance/test_FG_NNN_<slug>.sh` encoding the Gherkin (top-of-file `Covers:` block names the CAPs).
4. Implementation to turn test green (Dockerfile, sid pins, Makefile, GHA workflow).
5. Refactor + unit tests under `tests/unit/` for non-trivial helpers.
5a. **Register capabilities** — add or extend entries in `docs/CAPABILITIES.md`; ensure bidirectional links. `make verify-traceability` must pass.
6. `make check` passes (lint, pin-audit, traceability, acceptance tests). For image-touching changes: `make build && make scan && make verify` against a local digest.
6a. **Pre-ship audit** — fill the Shipping evidence table in the plan doc. Three lenses: **Gherkin coverage** (every Scenario has a test pointer), **build/scan/verify symmetry** (every image built → scanned → signed → verified; every CAP has a test), **self-consistency** (the story applies its own new conventions). Any ⚠️/❌ blocks shipping.
7. README updated only if the public contract changed (verify command, image set, roadmap).
8. PR to `dev` → user reviews → user merges. Next 03:00 UTC cron publishes it.

Exceptions (no story required): `fix/*` (with repro), `refactor/*` (acceptance tests prove invariance), `chore/*` (routine sid-pin add/remove, GHA tweak, dep bump), `docs/*`.

---

## Git workflow

- All work branches off `dev`. Branches: `feat/FG-NNN-<slug>`, `fix/<slug>`, `docs/<slug>`, `refactor/<slug>`, `chore/<slug>`
- `main` is CI-promoted only — never pushed to directly; on green `dev` merge CI fast-forwards `main` and the daily publish workflow picks up the new recipes
- Every `feat/*` and non-trivial `fix/*` needs `docs/plan/<slug>-plan.md` (template: `docs/plan/_template.md`)
- Commit format: `<type>(<scope>): <description>` — see `memory/code-quality.md`
