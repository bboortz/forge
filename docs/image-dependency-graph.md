# Forge Image Dependency Graph

Rendered from the actual Dockerfile `FROM` refs + `image.yaml` `depends_on` + `source:` blocks as of this document's commit. For the authoritative live state, see `grep -E "^FROM" images/*/Dockerfile`.

## Legend

- **Solid arrows** (`-->`): hard FROM dependency (parent must exist before child builds).
- **Dashed arrows** (`-.->`): COPY-from relationship — the parent is referenced but not FROMed. Covers both baseline overlay (`COPY --from=scratch_base / /`) and `/hc` healthcheck embed (`COPY --from=hc /hc /hc` — FG-031).

Images are grouped by role:
- **Upstream** (gray) — external to Forge (Docker Hub, GHCR, upstream git).
- **Forge pre-builders** (orange) — forge-rooted slim bases consumed by multiple downstream images (FG-042).
- **Forge builders** (blue) — never run at runtime; only used as builder-stage FROM refs.
- **Baseline** (green) — the shared `FROM scratch` + core closure overlay.
- **Slim runtime** (white) — consumer-facing; keeps shell + apt.
- **Scratch runtime** (yellow) — consumer-facing; `FROM scratch`.
- **External-sourced** (purple) — FG-012 pattern: Dockerfile + context pulled from an upstream git repo at build time.

## Diagram

```mermaid
graph TD
    %% ======================================================================
    %% Upstream (external to Forge)
    %% ======================================================================
    PY_UP["python:3.14-slim-trixie<br/>docker.io"]:::upstream
    GO_UP["golang:1.27-trixie<br/>docker.io"]:::upstream
    NODE_UP["node:24-trixie-slim<br/>docker.io"]:::upstream
    DEBIAN_UP["debian:trixie-slim<br/>docker.io"]:::upstream
    DEBIAN_SID_UP["debian:sid-slim<br/>docker.io"]:::upstream
    UBUNTU_UP["ubuntu:24.04<br/>docker.io"]:::upstream
    POSTGRES_UP["postgres:18<br/>docker.io"]:::upstream
    SYFT_UP["anchore/syft:latest<br/>docker.io"]:::upstream
    HC_UP["hc:0.1.0<br/>ghcr.io/bboortz<br/>(static Zig healthcheck)"]:::upstream
    BEACONRY_SRC["beaconry (source)<br/>github.com/bboortz/beaconry"]:::upstream

    %% ======================================================================
    %% Forge pre-builders (FG-042 / FG-051 / FG-058 / FG-061)
    %% ======================================================================
    DEBIAN_SLIM["debian-slim-trixie<br/>FG-042"]:::prebuilder
    DEBIAN_SID["debian-slim-sid<br/>FG-058 • zero consumers (infra)"]:::prebuilder
    PYSLIM["python-slim-trixie<br/>FG-001"]:::prebuilder
    UBUNTU_SLIM["ubuntu-slim-noble<br/>FG-051 • libicu74"]:::prebuilder
    NODE_SLIM["node-slim-trixie<br/>FG-061 • Node 24 LTS"]:::prebuilder

    %% ======================================================================
    %% Forge builders (never runtime)
    %% ======================================================================
    FBT["forge-builder-python-trixie<br/>FG-025 + FG-042 (dogfoods PYSLIM)"]:::builder
    FBG["forge-builder-go-trixie<br/>FG-046 • Go 1.27 + syft"]:::builder
    FBN["forge-builder-node-trixie<br/>FG-048 • Node 24 + syft"]:::builder

    %% ======================================================================
    %% Forge baseline
    %% ======================================================================
    SBT["scratch-base-trixie<br/>FG-005 • glibc+CA+nss"]:::baseline

    %% ======================================================================
    %% Slim runtimes (keep shell, apt kept)
    %% ======================================================================
    POSTGRES_SLIM["postgres-slim-trixie<br/>FG-026 + FG-054"]:::slim
    IPMI_SLIM["ipmi-exporter-slim-trixie<br/>FG-037 + FG-046 + FG-042"]:::slim
    CADVISOR["cadvisor-slim-trixie<br/>FG-044 + FG-046 + FG-042"]:::slim
    UK["uptime-kuma-slim-trixie<br/>FG-045/048/055/061"]:::slim
    RUNNER["github-runner-noble<br/>FG-051 • pre-baked GHA runner"]:::slim

    %% ======================================================================
    %% Scratch runtimes (FROM scratch + baseline overlay)
    %% ======================================================================
    PYSCR["python-scratch-trixie<br/>FG-003 + FG-009/011"]:::scratch
    NGINX["nginx-scratch-trixie<br/>FG-006 + FG-016/039/040"]:::scratch
    POSTGRES_SCR["postgres-scratch-trixie<br/>FG-007 + FG-026"]:::scratch
    REDIS["redis-scratch-trixie<br/>FG-027"]:::scratch
    MOSQ["mosquitto-scratch-trixie<br/>FG-028"]:::scratch
    HEALTHY["healthy-scratch-trixie<br/>FG-029"]:::scratch
    NODE_EX["node-exporter-scratch-trixie<br/>FG-034 + FG-046"]:::scratch
    PROM["prometheus-scratch-trixie<br/>FG-035 + FG-048 + FG-053"]:::scratch
    AM["alertmanager-scratch-trixie<br/>FG-036 + FG-046 + FG-052"]:::scratch
    IPMI_SCR["ipmi-exporter-scratch-trixie<br/>FG-043 + FG-046"]:::scratch

    %% ======================================================================
    %% External-sourced (FG-012 pattern)
    %% ======================================================================
    SCOUT["beaconry-scout<br/>FG-012"]:::external
    HUB["beaconry-hub<br/>FG-014"]:::external
    MOCK["beaconry-telegram-mock<br/>FG-015"]:::external

    %% ----------------------------------------------------------------------
    %% Upstream -> Forge pre-builders (FG-042 — literal FROM, one each)
    %% ----------------------------------------------------------------------
    DEBIAN_UP --> DEBIAN_SLIM
    DEBIAN_SID_UP --> DEBIAN_SID
    PY_UP --> PYSLIM
    UBUNTU_UP --> UBUNTU_SLIM
    NODE_UP --> NODE_SLIM

    %% ----------------------------------------------------------------------
    %% Forge pre-builders -> downstream
    %% ----------------------------------------------------------------------
    PYSLIM --> FBT
    DEBIAN_SLIM --> CADVISOR
    DEBIAN_SLIM --> IPMI_SLIM
    UBUNTU_SLIM --> RUNNER
    NODE_SLIM --> UK

    %% ----------------------------------------------------------------------
    %% Dedicated-toolchain exemptions — upstream consumed directly
    %% (ARG-indirect FROM; not grep-matched by verify-no-upstream-drift)
    %% ----------------------------------------------------------------------
    GO_UP --> FBG
    NODE_UP --> FBN
    POSTGRES_UP --> POSTGRES_SLIM

    %% ----------------------------------------------------------------------
    %% syft pulled into every builder base (FG-025/046/048)
    %% ----------------------------------------------------------------------
    SYFT_UP -.-> FBT
    SYFT_UP -.-> FBG
    SYFT_UP -.-> FBN

    %% ----------------------------------------------------------------------
    %% Forge builders used as builder-stage FROMs
    %% ----------------------------------------------------------------------
    FBT --> SBT
    FBT --> PYSCR
    FBT --> NGINX
    FBT --> POSTGRES_SCR
    FBT --> REDIS
    FBT --> MOSQ
    FBT --> HEALTHY
    FBT --> IPMI_SCR

    FBG --> CADVISOR
    FBG --> NODE_EX
    FBG --> AM
    FBG --> PROM
    FBG --> IPMI_SCR
    FBG --> IPMI_SLIM
    FBG --> POSTGRES_SLIM

    FBN --> UK
    FBN --> PROM
    FBN --> AM

    %% ----------------------------------------------------------------------
    %% Baseline overlay into scratch runtimes
    %% ----------------------------------------------------------------------
    SBT -.-> PYSCR
    SBT -.-> NGINX
    SBT -.-> POSTGRES_SCR
    SBT -.-> REDIS
    SBT -.-> MOSQ
    SBT -.-> HEALTHY
    SBT -.-> NODE_EX
    SBT -.-> PROM
    SBT -.-> AM
    SBT -.-> IPMI_SCR

    %% ----------------------------------------------------------------------
    %% /hc embed (FG-031) — healthcheck binary
    %% ----------------------------------------------------------------------
    HC_UP -.-> PYSCR
    HC_UP -.-> NGINX
    HC_UP -.-> POSTGRES_SCR
    HC_UP -.-> HEALTHY
    HC_UP -.-> NODE_EX
    HC_UP -.-> PROM
    HC_UP -.-> AM
    HC_UP -.-> IPMI_SCR
    HC_UP -.-> IPMI_SLIM
    HC_UP -.-> CADVISOR
    HC_UP -.-> UK

    %% ----------------------------------------------------------------------
    %% External-sourced (beaconry) — all three FROM python-scratch-trixie
    %% ----------------------------------------------------------------------
    BEACONRY_SRC -.-> SCOUT
    BEACONRY_SRC -.-> HUB
    BEACONRY_SRC -.-> MOCK
    PYSCR --> SCOUT
    PYSCR --> HUB
    PYSCR --> MOCK

    %% ======================================================================
    %% Styling
    %% ======================================================================
    classDef upstream   fill:#eeeeee,stroke:#999,stroke-width:1px,color:#333;
    classDef prebuilder fill:#fed7aa,stroke:#c2410c,stroke-width:2px,color:#7c2d12;
    classDef builder    fill:#dbeafe,stroke:#1e40af,stroke-width:2px,color:#1e3a8a;
    classDef baseline   fill:#bbf7d0,stroke:#166534,stroke-width:2px,color:#14532d;
    classDef slim       fill:#ffffff,stroke:#333,stroke-width:1px,color:#111;
    classDef scratch    fill:#fef3c7,stroke:#b45309,stroke-width:1px,color:#78350f;
    classDef external   fill:#ede9fe,stroke:#6d28d9,stroke-width:1px,color:#4c1d95;
```

## Facts behind the graph

### Trust-anchor consolidation (FG-042 → FG-051 → FG-058 → FG-061)

Every upstream Docker Hub anchor that fronts a generic slim base is consumed by **exactly one** forge pre-builder. Downstream slim / scratch images FROM the forge pre-builder, not the upstream directly.

| Upstream | Forge pre-builder | Downstream consumers |
|---|---|---|
| `python:3.14-slim-trixie` | `python-slim-trixie` (FG-001) | `forge-builder-python-trixie` (dogfood) |
| `debian:trixie-slim` | `debian-slim-trixie` (FG-042) | `cadvisor-slim-trixie`, `ipmi-exporter-slim-trixie` |
| `debian:sid-slim` | `debian-slim-sid` (FG-058) | — (escape-hatch infra for CVEs sid patches but trixie doesn't) |
| `ubuntu:24.04` | `ubuntu-slim-noble` (FG-051) | `github-runner-noble` |
| `node:24-trixie-slim` | `node-slim-trixie` (FG-061) | `uptime-kuma-slim-trixie` (runtime) |

Grep-invariant enforced by `scripts/verify-no-upstream-drift.sh`: `^FROM (debian:trixie-slim|debian:sid-slim|python:3.14-slim-trixie|ubuntu:24.04|node:24-trixie-slim)` matches exactly **5** Dockerfiles — the five pre-builders above. Everyone else goes through forge-signed intermediates.

### Dedicated-toolchain exemptions

Three upstreams bypass the pre-builder rule by design — each has exactly one Forge consumer and uses ARG-indirect `FROM ${X_BASE}` (not grep-matched by the drift guard):

| Upstream | Forge consumer | Why exempted |
|---|---|---|
| `golang:1.27-trixie` | `forge-builder-go-trixie` | Debian-packaged Go lags upstream by 3+ minor versions → stdlib CVE class. |
| `node:24-trixie-slim` | `forge-builder-node-trixie` | Debian-packaged Node is far behind the active LTS line. |
| `postgres:18` | `postgres-slim-trixie` | Compiling postgres from source is bigger than the drift risk justifies. |

Note: `node:24-trixie-slim` is **both** an anchor (via `node-slim-trixie`) and an exemption (via `forge-builder-node-trixie`). The literal `^FROM node:24-trixie-slim` fires once (pre-builder); the builder uses ARG indirection and so doesn't count toward `_EXPECTED`.

### Four-tier publish ordering

`.github/workflows/build.yml` publishes in this order (each tier gated on the previous via `needs:`):

1. **`publish-pre-builders`** (FG-042/051/058/061): `debian-slim-sid`, `debian-slim-trixie`, `node-slim-trixie`, `python-slim-trixie`, `ubuntu-slim-noble` in parallel.
2. **`publish-builders`** (FG-025/046/048): `forge-builder-go-trixie`, `forge-builder-node-trixie`, `forge-builder-python-trixie`. `forge-builder-python-trixie` FROMs `python-slim-trixie` (dogfood), so tier 1 must complete first.
3. **`publish-base`**: `scratch-base-trixie` + remaining single-consumer slim images + consumer-facing images (`cadvisor-slim`, `github-runner-noble`, `healthy-scratch`, `ipmi-exporter-slim`, `postgres-slim`, `uptime-kuma-slim`).
4. **`publish-derivatives`**: everything with `depends_on` (scratch variants + beaconry hub/scout/telegram-mock).

### Three builder lineages

1. **Python / Debian-apt builder** — `forge-builder-python-trixie` (FG-025, extended by FG-042): FROMs forge-signed `python-slim-trixie`. Used as the builder stage for every Debian-apt-install image. Current consumers: `scratch-base-trixie`, `python-scratch`, `nginx-scratch`, `postgres-scratch`, `redis-scratch`, `mosquitto-scratch`, `healthy-scratch`, `ipmi-exporter-scratch` (as C-builder).

2. **Go builder** — `forge-builder-go-trixie` (FG-046): `FROM golang:1.27-trixie` + apt-upgrade + CA + syft + git/curl/jq. Current consumers: `cadvisor-slim`, `node-exporter-scratch`, `alertmanager-scratch`, `prometheus-scratch`, `ipmi-exporter-{slim,scratch}`, `postgres-slim` (for building `gosu` from source — FG-054).

3. **Node builder** — `forge-builder-node-trixie` (FG-048): `FROM node:24-trixie-slim` + apt-upgrade + CA + syft + git/curl/jq + make/g++/python3 + dumb-init + corepack. Current consumers: `uptime-kuma-slim` (builder stage), `prometheus-scratch` (UI builder — React), `alertmanager-scratch` (UI builder — dual Elm + Mantine).

4. **Scratch baseline** — `scratch-base-trixie` (FG-005): the single `FROM scratch` image with glibc + CA + nss closure that every Forge scratch derivative overlays via `COPY --from=scratch_base / /`.

### Dual-/triple-builder patterns

- **`ipmi-exporter-scratch-trixie`** — dual-builder: `forge-builder-go-trixie` (go-builder, exporter binary) + `forge-builder-python-trixie` (c-builder, freeipmi tools via apt-install).
- **`prometheus-scratch-trixie`** — dual-builder: `forge-builder-node-trixie` (React UI via `npm run build` + `-tags builtinassets`) + `forge-builder-go-trixie` (prometheus + promtool binaries).
- **`alertmanager-scratch-trixie`** — dual-builder: `forge-builder-node-trixie` (both Elm classic UI + Mantine UI) + `forge-builder-go-trixie` (alertmanager binary — FG-052).

### `/hc` embed

`ghcr.io/bboortz/hc:0.1.0` is a ~400 KB static Zig binary implementing `/hc <url>` for in-container Docker `HEALTHCHECK`. Every image with a documented HEALTHCHECK carries it via `COPY --from=hc /hc /hc`. Independent of the builder/runtime chain.

### External-sourced (FG-012)

`beaconry-scout`, `beaconry-hub`, and `beaconry-telegram-mock` pull their Dockerfiles from `github.com/bboortz/beaconry` at build time (`source:` block in `image.yaml` names the git ref + dockerfile path). All three now FROM `python-scratch-trixie` — `beaconry-telegram-mock` was migrated off upstream `python:3.12-slim` in beaconry BC-100 to put every externally-sourced consumer on the forge-signed chain.

### Chain depth invariant (FG-042)

Current deepest chain: `debian:trixie-slim` (Docker Hub) → `python:3.14-slim-trixie` (Docker Hub) → `python-slim-trixie` (forge pre-builder) → `forge-builder-python-trixie` (forge builder) → `scratch-base-trixie` (forge baseline) → `python-scratch-trixie` / `nginx-scratch-trixie` / etc. = **5 hops to a scratch runtime** (cap). Node chain is shorter: `debian:trixie-slim` → `node:24-trixie-slim` → `node-slim-trixie` → `uptime-kuma-slim-trixie` = 3 hops.

## Regenerating

```bash
# Inspect current FROMs
grep -E "^FROM" images/*/Dockerfile

# Inspect declared depends_on
grep -lE "^depends_on:" images/*/image.yaml | xargs -r awk '/^depends_on:/,/^[^- ]/' /dev/null

# Inspect external-sourced
grep -lE "^source:" images/*/image.yaml

# Inspect pre-builders / builders / base / derivatives tier classification
for mode in pre-builders builders base derivatives; do
  echo "=== ${mode} ==="
  bash scripts/discover-images.sh "${mode}" | jq -r '.include[].image_dir'
done
```
