# Forge — top-level Makefile. See memory/workflow.md for the gate matrix.
#
# Primary variables (override via `make <target> VAR=value`):
#   IMAGE_NAME ?= python
#   IMAGE_TAG  ?= 3.13-slim-trixie
#   REGISTRY   ?= forge-local       (CI overrides to ghcr.io/bboortz)

IMAGE_NAME ?= python
IMAGE_TAG  ?= 3.13-slim-trixie
REGISTRY   ?= forge-local
OUT_DIR  ?= build

IMAGE      := $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
IMAGE_SLUG := $(IMAGE_NAME)-$(IMAGE_TAG)

SBOM       := $(OUT_DIR)/$(IMAGE_SLUG).sbom.json
GRYPE      := $(OUT_DIR)/$(IMAGE_SLUG).grype.json

COSIGN_DIR := .cosign
COSIGN_KEY := $(COSIGN_DIR)/cosign.key
COSIGN_PUB := $(COSIGN_DIR)/cosign.pub

LOCAL_REGISTRY_PORT ?= 5555
LOCAL_REGISTRY_NAME := forge-local-registry
LOCAL_IMAGE         := localhost:$(LOCAL_REGISTRY_PORT)/$(IMAGE_NAME):$(IMAGE_TAG)

ACCEPTANCE_TESTS := $(wildcard tests/acceptance/test_FG_*.sh)

.PHONY: help tools install-hooks lint build scan sign-local verify \
        test-images test-acceptance test-fast check \
        verify-sid-pins verify-traceability \
        _local-registry _local-registry-stop

help:
	@echo "Forge targets:"
	@echo "  tools                install cosign/grype/syft to ~/.local/bin if missing"
	@echo "  install-hooks        register pre-commit + pre-push git hooks locally"
	@echo "  lint                 hadolint / shellcheck / yamllint / actionlint"
	@echo "  verify-sid-pins      enforce CVE + removal condition + date per pin"
	@echo "  verify-traceability  enforce story ↔ plan ↔ test ↔ CAP links"
	@echo "  build                docker build images/<IMAGE_NAME>/ as $(IMAGE)"
	@echo "  scan                 syft SBOM + grype scan → $(OUT_DIR)/"
	@echo "  sign-local           push $(IMAGE) to localhost:$(LOCAL_REGISTRY_PORT) and cosign-sign"
	@echo "  verify               cosign verify (local key)"
	@echo "  test-images          bash images/*/tests/smoke_*.sh (scope with IMAGE_NAME)"
	@echo "  test-acceptance      bash tests/acceptance/test_FG_*.sh"
	@echo "  test-fast            lint + verify-sid-pins + verify-traceability"
	@echo "  check                test-fast + test-acceptance + test-images"
	@echo ""
	@echo "Variables: IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) REGISTRY=$(REGISTRY)"

tools:
	@mkdir -p $$HOME/.local/bin
	@command -v syft   >/dev/null || curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh  | sh -s -- -b $$HOME/.local/bin
	@command -v grype  >/dev/null || curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b $$HOME/.local/bin
	@command -v cosign >/dev/null || { curl -sSfL -o $$HOME/.local/bin/cosign https://github.com/sigstore/cosign/releases/download/v2.4.3/cosign-linux-amd64 && chmod +x $$HOME/.local/bin/cosign; }
	@command -v pre-commit >/dev/null || { echo "  pre-commit missing — install with: pipx install pre-commit"; false; }
	@for t in hadolint shellcheck yamllint actionlint jq; do \
	  command -v $$t >/dev/null || echo "  $$t missing (install via your package manager)"; \
	done

install-hooks:
	@command -v pre-commit >/dev/null || { echo "pre-commit missing — install with: pipx install pre-commit"; exit 1; }
	pre-commit install
	pre-commit install --hook-type pre-push

lint:
	@echo "→ hadolint"
	@hadolint images/*/Dockerfile
	@echo "→ shellcheck"
	@shellcheck tests/acceptance/*.sh images/*/build.sh scripts/*.sh
	@echo "→ yamllint"
	@yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}" .github/
	@if command -v actionlint >/dev/null; then echo "→ actionlint"; actionlint .github/workflows/*.yml; else echo "  actionlint missing — skipping"; fi

verify-sid-pins:
	@bash scripts/verify-sid-pins.sh

verify-traceability:
	@bash scripts/verify-traceability.sh

build:
	@bash images/$(IMAGE_NAME)/build.sh

scan: build
	@mkdir -p $(OUT_DIR)
	@echo "→ syft $(IMAGE) → $(SBOM)"
	@syft "$(IMAGE)" -o cyclonedx-json="$(SBOM)"
	@echo "→ grype $(IMAGE) → $(GRYPE)"
	@grype "$(IMAGE)" -o json > "$(GRYPE)" || true

_local-registry:
	@docker container inspect $(LOCAL_REGISTRY_NAME) >/dev/null 2>&1 || \
	  docker run -d --rm --name $(LOCAL_REGISTRY_NAME) -p $(LOCAL_REGISTRY_PORT):5000 registry:2 >/dev/null

_local-registry-stop:
	@docker rm -f $(LOCAL_REGISTRY_NAME) >/dev/null 2>&1 || true

$(COSIGN_KEY):
	@mkdir -p $(COSIGN_DIR)
	@echo "→ generating local cosign key pair under $(COSIGN_DIR)/"
	@cd $(COSIGN_DIR) && COSIGN_PASSWORD="" cosign generate-key-pair

sign-local: build _local-registry $(COSIGN_KEY)
	@docker tag $(IMAGE) $(LOCAL_IMAGE)
	@docker push $(LOCAL_IMAGE) >/dev/null
	@echo "→ cosign sign $(LOCAL_IMAGE)"
	@COSIGN_PASSWORD="" cosign sign --yes --key $(COSIGN_KEY) --tlog-upload=false --allow-insecure-registry $(LOCAL_IMAGE) >/dev/null

verify: $(COSIGN_PUB) _local-registry
	@echo "→ cosign verify $(LOCAL_IMAGE)"
	@COSIGN_PASSWORD="" cosign verify --key $(COSIGN_PUB) --insecure-ignore-tlog --allow-insecure-registry $(LOCAL_IMAGE) >/dev/null

test-acceptance:
	@for t in $(ACCEPTANCE_TESTS); do \
	  echo "→ $$t"; \
	  bash $$t || exit 1; \
	done

# test-images globs images/*/tests/smoke_*.sh and runs each against the
# already-built local image(s). Scope with IMAGE_NAME=python to narrow.
# Does NOT build the image itself — callers (acceptance test, make check)
# ensure a build has happened first.
test-images:
	@scope=$${IMAGE_NAME:+images/$$IMAGE_NAME/tests}; \
	scope=$${scope:-images/*/tests}; \
	found=0; fail=0; \
	for t in $$scope/smoke_*.sh; do \
	  [ -f "$$t" ] || continue; \
	  found=$$((found+1)); \
	  echo "→ $$t"; \
	  IMAGE_NAME="$(IMAGE_NAME)" IMAGE_TAG="$(IMAGE_TAG)" REGISTRY="$(REGISTRY)" \
	    bash "$$t" || fail=$$((fail+1)); \
	done; \
	echo "test-images: $$found script(s), $$fail failure(s)"; \
	[ $$fail -eq 0 ]

test-fast: lint verify-sid-pins verify-traceability

check: test-fast test-acceptance test-images
