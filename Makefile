# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

-include .env
export TENANT_ID TENANT_DOMAIN HSM_TYPE ENABLE_HELLO

.PHONY: all build bootstrap install run clean help
.DEFAULT_GOAL := help

all: build

build/.stamp-bootstrap:
	@mkdir -p build
	./bootstrap.sh build
	@touch $@

build/.stamp-install: build/.stamp-bootstrap
	./install.sh build
	@touch $@

bootstrap: build/.stamp-bootstrap ## Run bootstrap step (creates build/.stamp-bootstrap).
install: build/.stamp-install     ## Run install step (creates build/.stamp-install).
build: install                    ## Build operating system image (no-op if stamps are up-to-date).

run: build/.stamp-install ## Launch VM and open SPICE viewer (use BRIDGE=1 for bridged networking).
	@command -v remote-viewer >/dev/null 2>&1 || { echo "'remote-viewer' not found (install 'virt-viewer')." >&2; exit 1; }
	@set -eu; \
	BRIDGE_FLAG=""; \
	if [ "${BRIDGE:-0}" = "1" ]; then BRIDGE_FLAG="--bridge"; fi; \
	vm/init.sh $$BRIDGE_FLAG --config qemu.json build & \
	qemu_pid=$$!; \
	echo $$qemu_pid > build/qemu.pid; \
	for i in $$(seq 1 60); do \
		if [ -S build/spice.sock ]; then \
			break; \
		fi; \
		sleep 1; \
	done; \
	if [ ! -S build/spice.sock ]; then \
		echo "SPICE socket not found at build/spice.sock (timeout)"; \
		kill $$qemu_pid 2>/dev/null || true; \
		exit 1; \
	fi; \
	remote-viewer spice+unix://build/spice.sock

clean: ## Remove the build directory.
	@echo "Cleaning up build directory..."
	@-rm -rf build

help: ## Show the help message.
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
