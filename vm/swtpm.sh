#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <swtpm_directory>" >&2
  exit 1
fi

SWTPM_DIR="$1"
PID_FILE="$SWTPM_DIR/swtpm.pid"
LOG_FILE="$SWTPM_DIR/swtpm.log"
SOCKET_PATH="$SWTPM_DIR/swtpm.sock"

swtpm socket \
  --tpmstate "dir=$SWTPM_DIR" \
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
