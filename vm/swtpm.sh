#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

if [ $# -ne 2 ]; then
  echo "Usage: $(basename "$0") <swtpm_directory> <build_dir>" >&2
  exit 1
fi

SWTPM_DIR="$1"
BUILD_DIR="$2"

PID_FILE="$SWTPM_DIR/swtpm.pid"
LOG_FILE="$SWTPM_DIR/swtpm.log"
SOCKET_PATH="$SWTPM_DIR/swtpm.sock"
STATE_DIR="$SWTPM_DIR/state"

mkdir -p "$STATE_DIR"

# Ensure our per-build libtpms config is used (Infineon-like profile)
export LIBTPMS_CONF="$BUILD_DIR/swtpm-ca/libtpms.conf"

# Run swtpm_setup to manufacture the TPM and create EK cert only
# Use explicit config; omit platform cert by design.
swtpm_setup \
  --tpm2 \
  --tpmstate "$STATE_DIR" \
  --create-ek-cert \
  --lock-nvram \
  --overwrite \
  --config "$BUILD_DIR/swtpm-ca/swtpm_setup.conf"

# Start the TPM emulator pointing to the manufactured state
swtpm socket \
  --tpmstate "dir=$STATE_DIR" \
  --ctrl "type=unixio,path=$SOCKET_PATH" \
  --pid "file=$PID_FILE" \
  --log "file=$LOG_FILE,level=20" \
  --tpm2 \
  -d

timeout=0
while [ ! -S "$SOCKET_PATH" ]; do
  if [ "$timeout" -ge 10 ]; then
    echo "'$SOCKET_PATH' timed out" >&2
    exit 1
  fi
  sleep 1
  timeout=$((timeout + 1))
done

swtpm_pid=$(cat "$PID_FILE")
echo "$swtpm_pid $SOCKET_PATH"
