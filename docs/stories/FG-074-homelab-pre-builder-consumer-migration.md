---
id: FG-074
slug: homelab-pre-builder-consumer-migration
status: draft
owner: bboortz
created: 2026-11-20
---

# FG-074 — Homelab python-bot migration off `python-slim-trixie` pre-builder

Homelab consumes **`ghcr.io/bboortz/python-slim-trixie:latest`** as the FROM parent in 7 of its own bot Dockerfiles. This is a pre-flight finding before FG-070 (the `pre-builder/` tier migration) which will rename that GHCR repo to `ghcr.io/bboortz/pre-builder/python-slim-trixie`. Without a paired homelab update, the 7 bots' next rebuild will fail with "pull access denied" on the old path.

The user explicitly asked for this to be **tracked separately**, not solved during the tier migration.

## Findings — concrete audit

`grep -rn --include=Dockerfile '^FROM.*ghcr\.io/bboortz' /home/benni/git/homelab/`:

| Homelab Dockerfile | FROM line |
|---|---|
| `docker/brain-bot/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |
| `docker/ham-agent/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |
| `docker/homelab-bot/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |
| `docker/nextcloud-sync-mcp/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |
| `docker/cw-dashboard/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |
| `docker/ham-remote/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |
| `docker/kernel-test-bot/Dockerfile` | `FROM ghcr.io/bboortz/python-slim-trixie:latest` |

Plus one ansible variable at `ansible/inventory/group_vars/all/python.yml:2`:

```yaml
python3_slim_image: "ghcr.io/bboortz/python-slim-trixie"
```

No other L1 pre-builder is consumed as a FROM parent. No L2 builder, no L3 base. The surface is narrow — 7 Dockerfiles + 1 ansible var.

## 9 canonical answers

1. **Who** — homelab operator / forge maintainer. These two hats are usually the same human, but the story exists because the forge→homelab dependency is explicit and breaks on the FG-070 tag-move.

2. **When** — Fires when FG-070 lands on forge `dev` and the `python-slim-trixie` GHCR tag either moves to the new path or stops being published at the old path. If FG-070 ships with dual-publish (rejected per tier-plan O6), there's no fire; but we're not dual-publishing, so this story must land in lockstep with FG-070.

3. **What success looks like**:
   - All 7 homelab bot Dockerfiles updated to a chosen target (see § Options below).
   - Ansible var updated to match.
   - Each bot's CI (whichever pipeline it uses) rebuilds green.
   - Deployment to homeserver pulls the new image reference cleanly.

4. **Urgency** — Follows FG-070's cadence exactly. If FG-070 is scheduled, this story MUST land first (or simultaneously). Otherwise it's non-urgent.

5. **Happy path**:
   1. Pick one of the options in § Options below.
   2. Open homelab PR touching the 7 Dockerfiles + 1 ansible var.
   3. Wait until FG-070 forge PR has merged + main is promoted + the new `pre-builder/python-slim-trixie` tag is published.
   4. Merge the homelab PR (CI rebuilds green).
   5. Deploy to homeserver via the normal homelab ansible pipeline.

6. **Edge cases / failure modes**:
   - **Bot build caches referencing the old digest**: GHA / local Docker caches may hold the old layer. Rebuild from scratch after FG-070 ships to pick up the new image.
   - **Image tag drift**: homelab uses `:latest`. If a bot pulls while FG-070 is partway through publishing, it could race. Mitigate by ordering: forge publish green → then homelab merge.
   - **Ansible pull-timing**: `docker pull` on the homeserver ansible task needs to resolve the new path. The var change handles this.

7. **Out of scope**:
   - Rebuilding homelab's bot code or dependencies.
   - Changing the homelab bots' runtime (still Python slim on Debian trixie).
   - Forge-side dual-publish or backward-compat alias (rejected per tier-plan O6).

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.forge-rooted-slim-bases` — downstream consumer coordination tracked for this migration cycle.
   - EXT `build.pre-builder-tier` — demonstrates the "paired external PR" discipline that FG-070 relies on (per tier-plan O4).

## Options — pick one at implementation time

- **(A) Flip-the-path (minimal, recommended)**: Each of the 7 Dockerfiles updates `FROM ghcr.io/bboortz/python-slim-trixie:latest` → `FROM ghcr.io/bboortz/pre-builder/python-slim-trixie:latest`. Ansible var updates to match. Smallest possible diff; preserves existing Dockerfile logic + layer caching behavior.

- **(B) Migrate to an L4 runtime instead**: If Forge grows a dedicated "pythonic sidecar" L4 runtime (e.g., `python-slim-bot-trixie` tailored for homelab-style bot workloads), homelab's bots FROM that instead. More architectural work; defers the homelab PR.

- **(C) Semantic review — do the bots belong on the pre-builder at all?**: Pre-builders are "slim variants of upstream OS bases with apt-upgrade on top." Homelab bots use them as "a lean Python runtime." That's a valid pre-builder consumption pattern per the tier model — pre-builders DO keep shell + apt, which is what the bots need. Option (A) is correct; no architectural change is warranted.

**Recommendation**: Option (A). It's the least-surprise path and matches the tier-migration contract (consumers update their FROM; forge doesn't dual-publish).

## Gherkin acceptance

```
Scenario: all 7 homelab bot Dockerfiles updated to the new pre-builder path
  Given FG-070 has merged on forge dev + main
  And  ghcr.io/bboortz/pre-builder/python-slim-trixie:latest is published
  When homelab's 7 bot Dockerfiles are grepped
  Then every `^FROM.*python-slim-trixie` line references
       `ghcr.io/bboortz/pre-builder/python-slim-trixie:latest`
  And no line references the legacy flat `ghcr.io/bboortz/python-slim-trixie` path

Scenario: ansible inventory var matches
  Given the homelab repo after the PR merges
  Then ansible/inventory/group_vars/all/python.yml's `python3_slim_image`
       equals "ghcr.io/bboortz/pre-builder/python-slim-trixie"

Scenario: each bot rebuilds green on its CI
  Given the updated Dockerfiles
  When each bot's build pipeline runs
  Then `docker build` resolves the new FROM without "pull access denied"
  And the resulting image size + behavior is unchanged from pre-migration

Scenario: homeserver deployment picks up the new path
  Given the updated ansible inventory var
  When `ansible-playbook -i inventory homelab.yml` runs
  Then the python3-slim pull task uses the new ghcr path
  And existing bot containers restart successfully against the new base
```

## References

- Trigger: forge tier-migration plan `docs/plan/tier-layering-model.md` § FG-070 + O4
- Related forge FGs: FG-070 (the pre-builder/ tier move that causes this)
- Pre-flight audit: `grep -rn --include=Dockerfile '^FROM.*ghcr\.io/bboortz' /home/benni/git/homelab/` captured above
- Decision context: user instruction 2026-11-20 — "create a dedicated story to solve this but don't solve it immediately" during the FG-067→FG-071 autonomous run.

## Status + sequencing

This story is intentionally held at `draft` and is NOT implemented during the FG-067→FG-071 autonomous migration run. It must be picked up (status → ready → in-progress → shipped) in coordination with FG-070's merge window. The forge-side FG-070 story will reference FG-074 in its "Coordinated PRs" § as a must-ship-together item.
