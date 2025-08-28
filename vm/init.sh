#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

for cmd in getopt curl virt-fw-vars swtpm jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "'$cmd' not found" >&2
    exit 1
  fi
done

DEFAULT_CONFIG_FILE="qemu.json"
CONFIG_FILE=""
NETWORK_MODE="user"

opts=$(getopt -o bc: --long bridge,config: -n "$(basename "$0")" -- "$@")
if [ $? -ne 0 ]; then
    echo "Invalid options" >&2
    exit 1
fi
eval set -- "$opts"
while true; do
  case "$1" in
    -b | --bridge)
      NETWORK_MODE="bridge"
      shift
      ;;
    -c | --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
  esac
done

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") [-b|--bridge] [--config <file>] <output_dir>" >&2
  exit 1
fi

OUTPUT=$1

if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE="$DEFAULT_CONFIG_FILE"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "'$CONFIG_FILE' not found" >&2
  exit 1
fi

if [ ! -d "$OUTPUT" ]; then
  echo "'$OUTPUT' not found" >&2
  exit 1
fi

OVMF_VARS_TEMPLATE="$OUTPUT/OVMF_VARS.fd.template"
OVMF_VARS_INSTANCE="$OUTPUT/OVMF_VARS.fd"

if [ ! -f "$OVMF_VARS_TEMPLATE" ]; then
    echo "'$OVMF_VARS_TEMPLATE' not found" >&2
    exit 1
fi

# Boostrap UEFI variables file for the first boot.
if [ ! -f "$OVMF_VARS_INSTANCE" ]; then
    cp -v "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_INSTANCE"
    virt-fw-vars \
        --input "$OVMF_VARS_INSTANCE" \
        --output "$OVMF_VARS_INSTANCE" \
        --append-boot-filepath /EFI/debian/grubx64.efi
fi

swtpm_pid=""
swtpm_dir=""
teardown() {
  if [ -n "$swtpm_pid" ]; then
    kill -15 "$swtpm_pid" 2> /dev/null || true
  fi
}
trap teardown EXIT INT TERM
swtpm_dir=$(mktemp -d -t swtpm-XXXX)

mkdir -p "$swtpm_dir"

"vm/swtpm.sh" "$swtpm_dir" &
sleep 2

swtpm_pid=$(cat "$swtpm_dir/swtpm.pid")
swtpm_sock="$swtpm_dir/swtpm.sock"

if [ -z "$swtpm_pid" ]; then
    echo "'swtpm' not started" >&2
    exit 1
fi

"vm/qemu.sh" "$CONFIG_FILE" "$OUTPUT" "$NETWORK_MODE" "$swtpm_sock"
