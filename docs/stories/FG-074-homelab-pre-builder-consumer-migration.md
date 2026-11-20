---
id: FG-074
slug: homelab-pre-builder-consumer-migration
status: draft
owner: bboortz
created: 2026-11-20
---

# FG-074 — Homelab python-bot migration to `base/python-trixie` + pre-builder path-flip

Homelab consumes **`ghcr.io/bboortz/python-slim-trixie:latest`** as the FROM parent in 7 of its own bot Dockerfiles. This is a pre-flight finding before FG-070 (the `pre-builder/` tier migration) which will rename that GHCR repo to `ghcr.io/bboortz/pre-builder/python-slim-trixie`.

The **preferred solution** (per user direction, 2026-11-20) is **not a simple path-flip** — it's a *semantic* upgrade: migrate every bot that doesn't need runtime apt dependencies onto `base/python-trixie` (the scratch-overlay Python base from the L3 tier). This yields smaller images, zero runtime shell/apt attack surface, and dogfoods the tier model exactly the way it was designed. The subset of bots that need runtime apt stays on the pre-builder (with a mandatory path-flip to the new `pre-builder/` tier).

Held at `draft`; to be picked up when FG-070 enters its merge window.

## Audit — runtime dependency classification

`grep -A2 'FROM.*python-slim-trixie' Dockerfile` + manual review of each bot:

| Bot | pip install | Runtime apt install | Target in FG-074 |
|---|---|---|---|
| `brain-bot` | yes | **no** | 🟢 **Migrate → `base/python-trixie`** (scratch; multi-stage) |
| `ham-agent` | yes | **no** | 🟢 **Migrate → `base/python-trixie`** |
| `ham-remote` | yes | **no** | 🟢 **Migrate → `base/python-trixie`** |
| `cw-dashboard` | yes | **no** | 🟢 **Migrate → `base/python-trixie`** |
| `nextcloud-sync-mcp` | yes | build-time only (`gcc libffi-dev`, purged) | 🟢 **Migrate → `base/python-trixie`** (gcc only in builder stage) |
| `kernel-test-bot` | yes | **yes** (`util-linux` at runtime) | 🟡 **Stay on pre-builder** (path-flip to `pre-builder/python-slim-trixie`) |
| `homelab-bot` | yes | **yes** (`curl`, `docker.io`, `util-linux` at runtime) | 🟡 **Stay on pre-builder** (path-flip) |

**Bottom line**: 5 of 7 bots become scratch-overlay runtimes (shrink + harden). 2 bots stay as slim-with-shell images because their workloads (invoking `docker`, shelling out to `util-linux` tools) require apt-installed binaries at runtime.

Plus ansible var at `ansible/inventory/group_vars/all/python.yml:2`:

```yaml
python3_slim_image: "ghcr.io/bboortz/python-slim-trixie"
```

The ansible var still points at the slim pre-builder (`pre-builder/python-slim-trixie` after FG-070) — it's a generic "I need a python-slim base" reference used by the 2 bots that stay on pre-builder. No change needed if the 2 pre-builder-consuming bots continue to reference it; **the 5 migrated bots stop using the var** and reference `base/python-trixie` directly in their Dockerfile.

## 9 canonical answers

1. **Who** — homelab operator / forge maintainer. The semantic upgrade is a quality-of-service win for the 5 migrated bots (smaller, hardened); for the 2 that stay on pre-builder it's a minimal path-flip.

2. **When** — Fires in lockstep with FG-070 (forge pre-builder rename) **and** FG-069 (forge base/ tier migration — that's when `base/python-trixie` becomes pullable). Order of forge-side prerequisites:
   - FG-069 ships → `ghcr.io/bboortz/base/python-trixie:3.13` published
   - FG-070 ships → `ghcr.io/bboortz/pre-builder/python-slim-trixie:latest` published, old flat path stops updating
   - Then FG-074 homelab PR lands

3. **What success looks like**:
   - **5 migrated bots** (brain-bot, ham-agent, ham-remote, cw-dashboard, nextcloud-sync-mcp):
     - Two-stage Dockerfile; builder stage `FROM ghcr.io/bboortz/pre-builder/python-slim-trixie:latest` runs `pip install --target=/install`; runtime stage `FROM ghcr.io/bboortz/base/python-trixie:3.13` + `COPY --from=builder /install /usr/local/lib/python3.XX/site-packages` + app code
     - No shell in the resulting image; no pip; no apt; no site-packages churn at runtime
     - `nextcloud-sync-mcp`'s existing build-time `gcc libffi-dev` + purge pattern stays in the builder stage (pre-builder has apt there); runtime is scratch Python
   - **2 pre-builder-staying bots** (homelab-bot, kernel-test-bot): single-stage Dockerfile, FROM updated to `pre-builder/python-slim-trixie:latest`. All other logic unchanged.
   - `ansible/inventory/group_vars/all/python.yml` updated: `python3_slim_image: "ghcr.io/bboortz/pre-builder/python-slim-trixie"` (used by the 2 staying bots + any future generic-python ansible path).
   - Each bot rebuilds green on its CI.
   - Deployment to homeserver pulls all new references cleanly.
   - Measured size wins on the 5 migrated bots (expected ~70-80% shrink from slim ~90-100MB → scratch ~15-25MB for pure-Python bots).

4. **Urgency** — Follows FG-069 + FG-070's cadence. FG-074 is the final-leg coordinated PR; it merges after both forge FGs land on main.

5. **Happy path**:
   1. Wait until FG-069 merges + `base/python-trixie:3.13` publishes.
   2. Wait until FG-070 merges + `pre-builder/python-slim-trixie:latest` publishes.
   3. Open single homelab PR touching 7 Dockerfiles + 1 ansible var.
      - 5 Dockerfiles: rewrite to two-stage pattern per the template below.
      - 2 Dockerfiles: single-line FROM path change.
      - 1 ansible var: path change.
   4. Each bot's CI rebuilds green.
   5. Deploy to homeserver via standard ansible path; verify each bot pulls the new reference + starts successfully.
   6. Measure + record size delta per bot.

6. **Edge cases / failure modes**:
   - **Native-dep builds for migrated bots**: `nextcloud-sync-mcp` compiles `libffi` bindings via gcc. In the two-stage pattern, gcc installs cleanly in the builder stage; the compiled artifact lands in `/install` via `pip install --target`. No runtime gcc needed. If another bot develops a native-dep need later, the builder stage absorbs it; runtime stays scratch.
   - **Package data files**: packages that ship data files outside their Python package dir (e.g., some ML libs) may land in unexpected paths when installed via `pip --target`. Rare for bot-class workloads; mitigate by using `pip install --prefix=/install` instead of `--target` if a package misbehaves (`--prefix` respects the standard layout).
   - **Python interpreter version drift**: `base/python-trixie` ships a specific Python minor (3.14 at FG-069 time). Bots pin their builder stage's Python minor + the runtime's `base/python-trixie` tag to match. If upstream bumps `base/python-trixie` to 3.15, bots coordinate with the forge bump.
   - **Image-tag resolution race during migration**: homelab uses `:latest` for the pre-builder. If a bot pulls while FG-070 is mid-publish, the old-path pull could race. Mitigate by merging FG-074 **after** FG-070's publish is confirmed green.
   - **Debug workflow for operators**: 5 migrated bots have no shell. `docker exec -it <bot> bash` won't work. Operators switch to the forge-standard pattern: `docker logs` for stdout/stderr, `docker run --rm --entrypoint=/bin/sh pre-builder/python-slim-trixie:latest` as a sidecar for ad-hoc Python REPL work. Document in the migration PR's description.
   - **homelab-bot's docker.io runtime need**: `homelab-bot` invokes the docker CLI from inside its container (homelab-infra automation). This is why it stays on pre-builder — scratch has no docker CLI. If future refactoring removes the docker CLI need, homelab-bot can migrate to scratch too (separate FG).

7. **Out of scope**:
   - Changing bot application code or Python dependencies.
   - Compiling bots into a single static binary (e.g., PyInstaller / Nuitka) — architecturally different track; not the right lift here.
   - Forge-side dual-publish or backward-compat alias (rejected per tier-plan O6).
   - Growing a new forge image `python-bot-slim-trixie` with `curl`+`docker.io`+`util-linux` pre-baked — would be a forge L4 runtime for bot-class workloads. Scope-creep; revisit if a 3rd homelab bot develops runtime apt needs and justifies a shared runtime.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.forge-rooted-slim-bases` — downstream consumer coordination tracked for this migration cycle.
   - EXT `build.pre-builder-tier` — "paired external PR" discipline per tier-plan O4.
   - EXT `build.base-tier` (NEW in FG-069) — first external (non-beaconry) consumer of `base/python-trixie` via homelab bots.
   - EXT (soft) `image.zero-os-cves` — migrated bots inherit `base/python-trixie`'s scratch runtime CVE posture; their grype scan surface shrinks from Debian dpkg closure to just the pip-installed packages.

## Migration template — `base/python-trixie` two-stage

For the 5 bots moving to scratch:

```dockerfile
# syntax=docker/dockerfile:1.7
#
# Builder stage: pre-builder gives us pip + shell to install deps.
ARG PRE_BUILDER_REF=ghcr.io/bboortz/pre-builder/python-slim-trixie:latest
FROM ${PRE_BUILDER_REF} AS builder

# (optional) build-time apt for native deps — stays in builder stage only.
# RUN apt-get update && apt-get install -y --no-install-recommends gcc libffi-dev \
#  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
# Pin reproducibly — either requirements.txt (recommended) or inline list.
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# Runtime stage: scratch Python. No shell, no apt, no pip at runtime.
ARG BASE_PYTHON_REF=ghcr.io/bboortz/base/python-trixie:3.14
FROM ${BASE_PYTHON_REF}

# Overlay pip-installed packages.
COPY --from=builder /install /usr/local/lib/python3.14/site-packages

# App code.
COPY app.py /app/

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENTRYPOINT ["python3", "/app/app.py"]
```

Per-bot adaptation:
- `brain-bot`: replace `app.py` with `/app/brain_bot.py` and inline the 5 pip deps as a `requirements.txt`.
- `ham-agent`, `ham-remote`, `cw-dashboard`: same shape.
- `nextcloud-sync-mcp`: adds `gcc libffi-dev` apt-install in builder stage (`libffi` is a C ext).

## Gherkin acceptance

```
Scenario: 5 pure-Python bots migrated to base/python-trixie
  Given FG-069 + FG-070 have merged on forge dev + main
  And  ghcr.io/bboortz/base/python-trixie:3.14 is published
  And  ghcr.io/bboortz/pre-builder/python-slim-trixie:latest is published
  When homelab's 5 target bot Dockerfiles are grepped
  Then each has a `FROM ghcr.io/bboortz/pre-builder/python-slim-trixie` builder stage
  And each has a final `FROM ghcr.io/bboortz/base/python-trixie:3.14` runtime stage
  And no runtime stage contains `apt-get install` or `pip install`
  And no runtime stage contains `/bin/sh` invocation logic

Scenario: 2 apt-needing bots path-flipped on pre-builder
  Given FG-070 has merged
  When homelab's homelab-bot + kernel-test-bot Dockerfiles are grepped
  Then each has `FROM ghcr.io/bboortz/pre-builder/python-slim-trixie:latest`
  And no line references the legacy flat `ghcr.io/bboortz/python-slim-trixie` path

Scenario: ansible inventory var matches
  Given the homelab repo after the PR merges
  Then ansible/inventory/group_vars/all/python.yml's `python3_slim_image`
       equals "ghcr.io/bboortz/pre-builder/python-slim-trixie"

Scenario: all 7 bots rebuild green
  Given the updated Dockerfiles
  When each bot's build pipeline runs
  Then `docker build` resolves the new FROM references without "pull access denied"
  And each resulting image is runnable and the bot process starts

Scenario: 5 migrated bots are observably smaller
  Given the 5 pre-migration + 5 post-migration image size pairs
  When `docker image inspect --format={{.Size}}` is compared per bot
  Then each migrated bot's post-migration size is ≥ 50% smaller than pre-migration

Scenario: homeserver deployment picks up the new paths
  Given the updated ansible inventory var + Dockerfiles
  When `ansible-playbook -i inventory homelab.yml` runs
  Then docker pulls of the new refs succeed
  And existing bot containers restart against the new images
```

## References

- Trigger: forge tier-migration plan `docs/plan/tier-layering-model.md` § FG-069 + FG-070 + O4
- Related forge FGs:
  - FG-069 — introduces `base/python-trixie` (the scratch Python runtime base)
  - FG-070 — moves `python-slim-trixie` → `pre-builder/python-slim-trixie`
- Pre-flight audit: 2026-11-20 — 7 Dockerfiles + 1 ansible var captured above.
- Preferred-solution upgrade: user direction 2026-11-20 — "Better provide a better solution for FG 074 like having/using a base image from base tier."
- Precedent for the two-stage pattern:
  - FG-030 `healthy-scratch-trixie` — overlay a binary into scratch, no shell runtime
  - Beaconry hub/scout — `FROM python-scratch-trixie` as a runtime overlay (will become `base/python-trixie` post-FG-069)

## Status + sequencing

This story is intentionally held at `draft` and is NOT implemented during the FG-067→FG-071 autonomous migration run. It gets picked up (status → ready → in-progress → shipped) **after both FG-069 and FG-070 have merged** and their respective GHCR tags are published. Forge's FG-070 story references FG-074 in its "Coordinated PRs" § as a must-ship-together item; FG-074 will internally cite both.
