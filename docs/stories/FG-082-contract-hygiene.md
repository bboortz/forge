---
id: FG-082
slug: contract-hygiene
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-082 — Contract hygiene: retire stale `dumb-init` refs + backfill 4 orphan smoke promises

Two tidy-ups surfaced during post-FG-081 contract sweep. Zero image behaviour changes — only `PROMISES.yaml` + a Dockerfile comment + one smoke-size comment are touched.

## Category A — stale `dumb-init` references in `images/*/archlinux*/`

FG-081 shipped `pre-builder/archlinux` without `dumb-init` (not in Arch `core`/`extra`; AUR-only — see FG-081 story §6). Four prose/contract lines in the archlinux images still say "+ dumb-init" from an earlier implementation draft:

1. `images/pre-builder/archlinux/PROMISES.yaml:3` — file header
2. `images/pre-builder/archlinux/PROMISES.yaml:36` — size-budget description
3. `images/pre-builder/archlinux/tests/smoke_size.sh:2` — smoke header comment
4. `images/base/archlinux/Dockerfile:14` — composition comment

The explicit `# DELTA vs other forge pre-builders: dumb-init is NOT shipped. ...` note at `pre-builder/archlinux/Dockerfile:16-20` and the matching LABEL line are the current truth and **stay**. The four stale lines contradict them one scroll away — worst-case a future reader trusts the stale `PROMISES.yaml` claim.

## Category B — four orphan smokes not registered in any `PROMISES.yaml`

These smoke scripts live in-tree, run in CI via `make test-images`, but no `PROMISES.yaml` promise entry points at them. That's a DD-TGD gap: the test proves something but the contract doesn't state it. `verify-traceability` passes today only because it enforces promise→test, not test→promise.

| Smoke | Image | Extends CAP | New promise id |
|---|---|---|---|
| `tests/smoke_ipmi_collector_uses_elf.sh` | `ipmi-exporter-scratch-trixie` | `image.ipmi-exporter-serves-metrics` | `absence.shell-wrapper-dependency` |
| `tests/smoke_console_files.sh` | `prometheus-scratch-trixie` | `image.prometheus-serves-metrics` | `files.console-templates` |
| `tests/smoke_lifecycle_reload.sh` | `prometheus-scratch-trixie` | `image.prometheus-serves-metrics` | `runtime.lifecycle-reload` |
| `tests/smoke_ping_available.sh` | `uptime-kuma-slim-trixie` | `image.uptime-kuma-serves-monitoring` | `files.ping-binary` |

No new CAPs — all 4 extend existing CAPs.

## 9 canonical answers

1. **Who** — Forge maintainer (contract audit); future operator reading PROMISES as the source of truth.
2. **When** — Fires post-FG-081 contract audit; blocks nothing but calcifies into tech debt if deferred.
3. **What** — ✅ 4 archlinux files no longer mention dumb-init; ✅ 4 orphan smokes have a promise line; ✅ `verify-traceability` + CI acceptance tests still green.
4. **Urgency** — Quality-of-life. Low-impact until a new contributor reads a stale `PROMISES.yaml` line and trusts it.
5. **Happy path** —
   1. Edit 4 archlinux files; drop the `+ dumb-init` phrase.
   2. Edit 3 PROMISES files; add 4 promise entries pointing at the orphan smokes.
   3. `make test-fast` green; new FG-082 acceptance red → green.
   4. Ship via usual PR → dev → release → build cadence.
6. **Edge cases / failure modes** —
   - Promise id collisions — none (all 4 ids are new to their respective files).
   - Scope creep into "add verify-no-orphan-smokes.sh" invariant — explicitly deferred; see §7.
   - Rebasing noise — these are small text edits; no risk.
7. **Out of scope** —
   - A new `scripts/verify-no-orphan-smokes.sh` policy script (would need a separate story; adds enforcement muscle but is net-new behaviour, not hygiene).
   - PROMISES `version:` vs `image.yaml` `tag:` systemic mismatch — intentional (contract-schema version, not image release version).
   - New CAPs.
   - Image-level behaviour changes.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_082_contract-hygiene.sh`. 4 stale refs removed; 4 orphans registered; CI green.
9. **Capabilities delivered or extended** —
   - EXT `image.ipmi-exporter-serves-metrics` — new promise `absence.shell-wrapper-dependency`.
   - EXT `image.prometheus-serves-metrics` — new promises `files.console-templates`, `runtime.lifecycle-reload`.
   - EXT `image.uptime-kuma-serves-monitoring` — new promise `files.ping-binary`.

## Gherkin acceptance

```
Scenario: no "+ dumb-init" strings in the four target archlinux files
  Given FG-082 has shipped
  Then grep "dumb-init" inside pre-builder/archlinux/PROMISES.yaml header + size-budget
   And grep "dumb-init" inside pre-builder/archlinux/tests/smoke_size.sh header
   And grep "+ dumb-init" inside base/archlinux/Dockerfile
   All return no matches
   But pre-builder/archlinux/Dockerfile's "DELTA ... dumb-init is NOT shipped" note stays

Scenario: 4 orphan smokes are referenced by a PROMISES entry
  Given FG-082 has shipped
  Then ipmi-exporter-scratch-trixie/PROMISES.yaml references smoke_ipmi_collector_uses_elf.sh
   And prometheus-scratch-trixie/PROMISES.yaml references smoke_console_files.sh + smoke_lifecycle_reload.sh
   And uptime-kuma-slim-trixie/PROMISES.yaml references smoke_ping_available.sh

Scenario: no new CAPs, no new images
  Given FG-082 has shipped
  Then docs/CAPABILITIES.md CAP count is unchanged from pre-FG-082
   And no images/ directory was added

Scenario: traceability + test-fast still green
  Given FG-082 has shipped
  Then make test-fast exits 0
   And bash scripts/verify-traceability.sh exits 0
```

## References

- Plan: `docs/plan/FG-082-contract-hygiene-plan.md`
- Red test: `tests/acceptance/test_FG_082_contract-hygiene.sh`
- Upstream reason: FG-081 archlinux pivot dropped dumb-init (Arch core/extra lacks it)
- Pattern precedent: there is none — this is the first dedicated "contract hygiene" FG. Future similar sweeps use this as the template.
