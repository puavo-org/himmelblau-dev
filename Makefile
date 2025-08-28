#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

BUILD_DIR := build

-include .env
export TENANT_ID TENANT_DOMAIN

BUILD_FLAGS :=
ifeq ($(UPDATE),true)
  BUILD_FLAGS += --update
endif

RUN_FLAGS :=
ifeq ($(BRIDGE),true)
  RUN_FLAGS += --bridge
endif

.PHONY: all build-image bootstrap configure-vm run-vm clean help

all: build-image

build: bootstrap configure-vm ## Build image. Use 'UPDATE=1' to update Himmelblau.

bootstrap:
	./bootstrap/init.sh $(BUILD_FLAGS) $(BUILD_DIR)

configure-vm:
	./config/init.sh $(BUILD_DIR)

run: ## Run image inside QEMU. Use 'BRIDGE=1' for bridged network.
	./vm/init.sh $(RUN_FLAGS) $(BUILD_DIR)

clean: ## Remove the build directory.
	@echo "Cleaning up build directory..."
	@-rm -rf $(BUILD_DIR)

help: ## Show the help message.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
