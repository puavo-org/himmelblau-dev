# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Opinsys Oy

-include .env
export TENANT_ID TENANT_DOMAIN HSM_TYPE ENABLE_HELLO

DOCKER ?= docker

.PHONY: all build bootstrap image install clean help
.DEFAULT_GOAL := help

all: build

build/himmelblau-demo.qcow2:
	@mkdir -p build
	@cp himmelblau.version build/
	@cp systemd-creds-wrapper.sh build/
	@set -eu; \
	COMPOSE_CMD=""; \
	if command -v "$(DOCKER)" >/dev/null 2>&1; then \
		if "$(DOCKER)" compose version >/dev/null 2>&1; then \
			COMPOSE_CMD="$(DOCKER) compose"; \
		fi; \
	fi; \
	if [ -z "$$COMPOSE_CMD" ]; then \
		if command -v "$(DOCKER)-compose" >/dev/null 2>&1; then \
			COMPOSE_CMD="$(DOCKER)-compose"; \
		fi; \
	fi; \
	if [ -z "$$COMPOSE_CMD" ]; then \
		echo "No compose frontend found for '$(DOCKER)' (tried '$(DOCKER) compose' and '$(DOCKER)-compose')." >&2; \
		exit 1; \
	fi; \
	$$COMPOSE_CMD run --rm himmelblau-demo-builder; \
	if [ ! -f build/himmelblau-demo.qcow2 ]; then \
		echo "Image was not created in build/." >&2; \
		exit 1; \
	fi

build/.stamp-ovmf:
	@mkdir -p build
	./bootstrap.sh build
	@touch $@

bootstrap: build/.stamp-ovmf      ## Prepare OVMF firmware (auto-run by build).
image: build/himmelblau-demo.qcow2 ## Build operating system image.

build: ## Build image and prepare firmware.
	$(MAKE) image
	$(MAKE) bootstrap

install: build ## Create or update libvirt domain using virt-install.
	./virt-install.sh build

clean: ## Remove the build directory.
	@echo "Cleaning up build directory..."
	@-rm -rf build

help: ## Show the help message.
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
