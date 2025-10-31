#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

for cmd in getopt virt-fw-vars swtpm jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "'$cmd' not found" >&2
    exit 1
  fi
done

ARG_CONFIG="qemu.json"
ARG_BRIDGE=0

opts=$(getopt -o bc: --long bridge,config: -n "$(basename "$0")" -- "$@")
if [ $? -ne 0 ]; then
    echo "Invalid options" >&2
    exit 1
fi
eval set -- "$opts"
while true; do
  case "$1" in
    -b | --bridge)
      ARG_BRIDGE=1
      shift
      ;;
    -c | --config)
      ARG_CONFIG="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
  esac
done

if [ "$ARG_BRIDGE" -eq 1 ]; then
  NETWORK="bridge"
else
  NETWORK="user"
fi
echo "vm: network=$NETWORK"

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") [-b|--bridge] [--config <file>] <output_dir>" >&2
  exit 1
fi

BUILD_DIR=$1

if [ ! -f "$ARG_CONFIG" ]; then
  echo "'$ARG_CONFIG' not found" >&2
  exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
  echo "'$BUILD_DIR' not found" >&2
  exit 1
fi

OVMF_VARS_TEMPLATE="$BUILD_DIR/OVMF_VARS.fd.template"
OVMF_VARS_INSTANCE="$BUILD_DIR/OVMF_VARS.fd"

if [ ! -f "$OVMF_VARS_TEMPLATE" ]; then
    echo "'$OVMF_VARS_TEMPLATE' not found" >&2
    exit 1
fi

# Bootstrap UEFI variables file for the first boot.
if [ ! -f "$OVMF_VARS_INSTANCE" ]; then
    cp -v "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_INSTANCE"
    virt-fw-vars \
        --input "$OVMF_VARS_INSTANCE" \
        --output "$OVMF_VARS_INSTANCE" \
        --append-boot-filepath /EFI/debian/grubx64.efi
fi

swtpm_pid=""
swtpm_dir="$BUILD_DIR/swtpm"
swtpm_sock="$swtpm_dir/swtpm.sock"
swtpm_pidfile="$swtpm_dir/swtpm.pid"

teardown() {
  if [ -n "$swtpm_pid" ]; then
    kill -15 "$swtpm_pid" 2> /dev/null || true
  fi
}
trap teardown EXIT INT TERM

mkdir -p "$swtpm_dir"

"vm/swtpm.sh" "$swtpm_dir" &

tries=0
max_tries=120
while [ ! -S "$swtpm_sock" ]; do
  if [ "$tries" -ge "$max_tries" ]; then
    echo "'swtpm' did not become ready (no socket at $swtpm_sock)" >&2
    exit 1
  fi
  sleep 1
  tries=$((tries + 1))
done

tries=0
while [ ! -f "$swtpm_pidfile" ]; do
  if [ "$tries" -ge 10 ]; then
    echo "'swtpm' is ready but no pid file found at $swtpm_pidfile" >&2
    break
  fi
  sleep 1
  tries=$((tries + 1))
done

if [ -f "$swtpm_pidfile" ]; then
  swtpm_pid=$(cat "$swtpm_pidfile" || true)
fi

if [ -z "${swtpm_pid:-}" ]; then
  echo "Warning: could not read swtpm PID; proceeding since socket is ready at $swtpm_sock"
fi

"vm/qemu.sh" "$ARG_CONFIG" "$BUILD_DIR" "$NETWORK" "$swtpm_sock"
