*Development workflow for Forge. Design-Driven, Test-Guarded (DD-TGD) — every change is traceable from a user story through a plan doc through a red acceptance test to the signed, scanned, published digest.*

## Quality bar

**Every published digest is traceable** back to the story that motivated it (`docs/stories/FG-NNN-<slug>.md`), the plan that scoped it (`docs/plan/FG-NNN-<slug>-plan.md`), the acceptance test that proves it (`tests/acceptance/test_FG_NNN_<slug>.sh`), and the signed attestations that let a consumer verify it. If any link is missing, the change is not shippable.

## Development process: Design-Driven, Test-Guarded (DD-TGD)

```
Per feature (FG-NNN):
0.  Consult IDEAS backlog   docs/plan/IDEAS.md — ideas not yet promoted to stories.
1.  Consumer/maintainer     docs/stories/FG-NNN-<slug>.md
    story                   9 canonical questions → Gherkin acceptance + CAP list.
                            Status: draft → ready.
2.  Branch + plan doc       feat/FG-NNN-<slug> from dev
                            docs/plan/FG-NNN-<slug>-plan.md:
                              - Story link, design delta, alternatives rejected
                              - Breaking changes (public verify cmd? consumer pulls?)
                              - Merge plan + rollout plan
                              - Shipping evidence table (filled at 6a)
                            Story status → in-progress.
3.  Red acceptance test     tests/acceptance/test_FG_NNN_<slug>.sh
                            Gherkin as shell assertions (make build / scan / verify
                            + jq). Top-of-file `Covers:` block names CAPs.
                            Must fail before implementation.
4.  Implementation          Smallest change that turns the red test green.
5.  Refactor + helpers      tests/unit/ (bats) for non-trivial helpers.
                            Every test file carries a `Covers:` block.
5a. Register capabilities   docs/CAPABILITIES.md — add/extend entries; bidirectional
                            links checked by make verify-traceability.
6.  Gates                   make check (see matrix below). For image-touching
                            changes also: make build + scan + verify locally.
6a. Pre-ship audit          Fill Shipping evidence table. Three lenses:
                              - Gherkin coverage (every Scenario → test pointer)
                              - Build/scan/verify symmetry (every image/CAP → test)
                              - Self-consistency (story applies its own conventions)
                            Any ⚠️/❌ row blocks shipping — cycle back to step 5.
7.  Update README           Only if public contract changed.
8.  Push + PR + auto-merge  Claude pushes branch, opens PR to dev with body
                            linking story + plan + grype-diff. CI runs full
                            tier on PR. Claude merges to dev on green CI
                            without a second prompt — user only intervenes
                            if the PR needs discussion. Story → shipped on
                            merge. Dev → main is a separate manual promotion
                            via .github/workflows/release.yml; the daily
                            cron publishes from main.
```

**Exceptions (no story required):**
- `fix/<slug>` with a clear repro — one-line fix, repro referenced in commit
- `refactor/<slug>` — acceptance tests prove behaviour invariance
- `chore/<slug>` — routine sid-pin add/remove, GHA tweak, dep bump
- `docs/<slug>` — docs only

**Definition of Done per FG-NNN:**
- [ ] Red acceptance test went green via implementation
- [ ] Capabilities registered + bidirectional links present
- [ ] All blocking gates pass
- [ ] Shipping evidence table has no ⚠️/❌ rows
- [ ] README updated if public contract changed
- [ ] Smoke test added if a new image was introduced

## Stories — layout, format, lifecycle

```
docs/stories/
  INDEX.md             — one-line status board (grep-friendly)
  _template.md         — canonical story template
  _9-questions.md      — the canonical clarification set
  FG-NNN-<slug>.md     — one file per story
```

Lifecycle: `draft → ready → in-progress → shipped` (frontmatter + INDEX).

**The 9 canonical clarification questions** (asked for every new story):

1. **Who** is the consumer in this moment? (Python dev / security engineer / ops / auditor / Forge maintainer)
2. **When** does the story fire? (trigger — new CVE in sid, consumer verifies image, maintainer adds image, auditor runs compliance report)
3. **What** does success look like? (observable: grype clean, cosign verify green, specific tag resolves, image size X)
4. **How urgent?** (impact tier — security-critical / correctness / quality-of-life)
5. **Happy path** — exact sequence of consumer or pipeline steps?
6. **Edge cases / failure modes** that matter?
7. **Out of scope** — what could creep in but shouldn't?
8. **How do we know it's done?** (acceptance = Gherkin)
9. **What capabilities does this story deliver or extend?** — Name new CAP ids; link to existing ones. Make the capability matrix explicit from story-time, not retroactively.

## Capability matrix

`docs/CAPABILITIES.md` is the source of truth for what Forge can do, with bidirectional links to the acceptance tests. Example CAP ids: `build.two-stage-scratch`, `build.multi-arch`, `pins.sid-pin`, `pins.audit-staleness`, `scan.grype-attest`, `scan.regression-gate`, `sbom.cyclonedx-attest`, `sign.cosign-keyless-oidc`, `sign.cosign-local-dev`, `verify.consumer-cmd`, `publish.daily-cron`, `publish.date-tagged-aliases`, `publish.ghcr-public-pull`.

`make verify-traceability` enforces: every CAP has ≥1 test pointer; every acceptance test's `Covers:` block names only known CAPs; every `ready+` story has at least one CAP in question 9.

## Blocking gates (must pass to merge to `dev`)

| Gate | Tool | Where |
|------|------|-------|
| Lint — Dockerfiles | `hadolint` | pre-commit + `make check` |
| Lint — shell | `shellcheck` | pre-commit + `make check` |
| Lint — YAML (GHA) | `yamllint` + `actionlint` | pre-commit + `make check` |
| sid-pin audit | `make verify-sid-pins` (CVE + removal condition per pin) | pre-commit + `make check` |
| Traceability | `make verify-traceability` | pre-commit + `make check` |
| Acceptance tests | `make test-acceptance` | pre-push + PR CI |
| Build | `make build` from clean cache | PR CI |
| Scan | `make scan` — grype finishes | PR CI |
| Scan regression | PR scan has no new HIGH/CRITICAL vs. current `:latest` | PR CI |
| Verify | `make verify` — cosign verify succeeds | PR CI + nightly |
| Image size | `make size` — not larger than previous `:latest` by > 10% | PR CI |

No advisory gates — if a check isn't worth blocking, it isn't worth running.

## Testing strategy

```
tests/
  acceptance/   — one shell test per FG-NNN story; Gherkin as make+jq+cosign asserts
  unit/         — bats / shellcheck'd shell for helpers (ldd closure gen, jq filters)
  fixtures/     — sample grype JSON, sample sid-pin files, test SBOMs
  smoke/        — pull-and-run a published image: python3 -c "print(1)"
```

Mocking rule: cosign / grype / syft run for real against local test images — no mocks worth maintaining. Trade-off: full suite takes minutes, not seconds; mitigate with `make test-fast` that skips image builds.

## Branch flow & release pipeline

- Work branches off `dev`: `feat/FG-NNN-<slug>`, `fix/<slug>`, `docs/<slug>`, `refactor/<slug>`, `chore/<slug>`.
- Claude auto-merges to `dev` on green CI per step 8. Human intervenes only when the PR needs discussion.
- `main` is CI-promoted only. `.github/workflows/release.yml` is a manual `workflow_dispatch` that asserts dev's CI is green then fast-forwards main from dev. User triggers it.
- Daily publish (`build.yml`) runs off `main`. New recipes don't reach consumers until `main` moves.
- CI tiers (`.github/workflows/ci.yml`): feat/fix/docs/chore/refactor push → fast (lint + verify-*). `dev` push + PRs to `dev` → full (`make check` = fast + acceptance). `main` push → release-check (minimal in V1).

## Dev-loop ergonomics

- **Local env**: Docker + hadolint + shellcheck + cosign (v2.x) + grype + syft + bats + yamllint + actionlint. `make tools` installs the missing CLIs that have official installers; the rest come from the host package manager.
- **Makefile targets**: `make lint`, `make build`, `make scan`, `make sign-local`, `make verify`, `make test-acceptance`, `make test-fast`, `make check`, `make check-strict`, `make clean-local-images`, `make verify-traceability`, `make verify-sid-pins`.
- **Pre-commit hooks** (`.pre-commit-config.yaml`) — install with `make install-hooks`:
  - On `commit` (fast, staged files): hadolint + shellcheck + yamllint; verify-sid-pins when `sid-pins/` changed; verify-traceability when story / plan / test / CAP paths touched.
  - On `push` (full repo): `make check-strict` = `clean-local-images` + `check`. Wiping every `forge-local/*` image first catches stale image refs in tests that would otherwise hide behind the workstation's docker cache (hard-learned via PR #7 CI failure). Bypass with `--no-verify` only in emergencies.

## When adding a new image — checklist

- [ ] Story reaches `ready` via 9-question pass
- [ ] Plan doc landed with design delta + rollout
- [ ] Red acceptance test in `tests/acceptance/test_FG_NNN_<slug>.sh`
- [ ] Dockerfile two-stage; hadolint clean
- [ ] `images/<name>/build.sh` written (`set -euo pipefail`)
- [ ] Wired into Makefile + `.github/workflows/{build,pr}.yml`
- [ ] CAPs registered in `docs/CAPABILITIES.md`; bidirectional links present
- [ ] Shipping evidence table ✅
- [ ] First grype scan captured as baseline
- [ ] README `§ Images` table updated when ready to publish
