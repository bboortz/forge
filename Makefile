# Forge — top-level Makefile. See memory/workflow.md for the gate matrix.
#
# Primary variables (override via `make <target> VAR=value`):
#   IMAGE_DIR  ?= python-slim-trixie    (directory under images/)
#   REGISTRY   ?= forge-local           (CI overrides to ghcr.io/bboortz)
#
# Repo + tag are resolved from images/<IMAGE_DIR>/image.yaml so callers only
# ever pass IMAGE_DIR. test-images delegates to scripts/test-images.sh which
# does its own yaml resolution.

IMAGE_DIR ?= python-slim-trixie
REGISTRY  ?= forge-local
OUT_DIR   ?= build

# Resolve repo + tag from the image's yaml (only when the dir exists; empty
# otherwise so `make help` etc. stay usable).
_IMAGE_YAML := images/$(IMAGE_DIR)/image.yaml
_REPO := $(if $(wildcard $(_IMAGE_YAML)),$(shell awk '/^repo:/ {print $$2; exit}' $(_IMAGE_YAML)))
_TAG  := $(if $(wildcard $(_IMAGE_YAML)),$(shell awk '/^tag:/  {print $$2; exit}' $(_IMAGE_YAML)))
IMAGE := $(REGISTRY)/$(_REPO):$(_TAG)
IMAGE_SLUG := $(_REPO)-$(_TAG)

SBOM  := $(OUT_DIR)/$(IMAGE_SLUG).sbom.json
GRYPE := $(OUT_DIR)/$(IMAGE_SLUG).grype.json

COSIGN_DIR := .cosign
COSIGN_KEY := $(COSIGN_DIR)/cosign.key
COSIGN_PUB := $(COSIGN_DIR)/cosign.pub

LOCAL_REGISTRY_PORT ?= 5555
LOCAL_REGISTRY_NAME := forge-local-registry
LOCAL_IMAGE         := localhost:$(LOCAL_REGISTRY_PORT)/$(_REPO):$(_TAG)

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
	@echo "  build                scripts/build-image.sh \$$IMAGE_DIR"
	@echo "  scan                 syft SBOM + grype scan → $(OUT_DIR)/"
	@echo "  sign-local           push $(IMAGE) to localhost:$(LOCAL_REGISTRY_PORT) and cosign-sign"
	@echo "  verify               cosign verify (local key)"
	@echo "  test-images          scripts/test-images.sh [\$$IMAGE_DIR]"
	@echo "  test-acceptance      bash tests/acceptance/test_FG_*.sh"
	@echo "  test-fast            lint + verify-sid-pins + verify-traceability"
	@echo "  check                test-fast + test-acceptance + test-images"
	@echo ""
	@echo "Variables: IMAGE_DIR=$(IMAGE_DIR) REGISTRY=$(REGISTRY)"
	@echo "Resolved:  IMAGE=$(IMAGE)"

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
	@shellcheck tests/acceptance/*.sh images/*/tests/*.sh scripts/*.sh
	@echo "→ yamllint"
	@yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}" .github/ images/*/image.yaml
	@if command -v actionlint >/dev/null; then echo "→ actionlint"; actionlint .github/workflows/*.yml; else echo "  actionlint missing — skipping"; fi

verify-sid-pins:
	@bash scripts/verify-sid-pins.sh

verify-traceability:
	@bash scripts/verify-traceability.sh

build:
	@bash scripts/build-image.sh "$(IMAGE_DIR)"

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

test-images:
	@bash scripts/test-images.sh

test-fast: lint verify-sid-pins verify-traceability

check: test-fast test-acceptance test-images
