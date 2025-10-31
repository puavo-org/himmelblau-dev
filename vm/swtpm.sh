#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <swtpm_directory>" >&2
  exit 1
fi

case "$1" in
  /*) SWTPM_DIR="$1" ;;
  *)  SWTPM_DIR="$(cd "$1" >/dev/null 2>&1 && pwd -P)" ;;
esac

PID_FILE="$SWTPM_DIR/swtpm.pid"
LOG_FILE="$SWTPM_DIR/swtpm.log"
SOCKET_PATH="$SWTPM_DIR/swtpm.sock"

SWTPM_STATE_DIR="$SWTPM_DIR/state"
SWTPM_CONF_DIR="$SWTPM_DIR/config"
SWTPM_LOCALCA_DIR="$SWTPM_DIR/localca"

cd "${0%/*}/"

mkdir -p "$SWTPM_STATE_DIR" "$SWTPM_CONF_DIR" "$SWTPM_LOCALCA_DIR"
chmod 700 "$SWTPM_STATE_DIR" "$SWTPM_LOCALCA_DIR"

cat >"$SWTPM_CONF_DIR/swtpm-localca.conf" <<EOF
statedir = $SWTPM_LOCALCA_DIR
signingkey = $SWTPM_LOCALCA_DIR/signkey.pem
issuercert = $SWTPM_LOCALCA_DIR/issuercert.pem
certserial = $SWTPM_LOCALCA_DIR/certserial
EOF

cat >"$SWTPM_CONF_DIR/swtpm-localca.options" <<\EOF
--platform-manufacturer Himmelblau
--platform-version 0
--platform-model QEMU
EOF

cat >"$SWTPM_CONF_DIR/swtpm_setup.conf" <<EOF
create_certs_tool = swtpm_localca
create_certs_tool_config = $SWTPM_CONF_DIR/swtpm-localca.conf
create_certs_tool_options = $SWTPM_CONF_DIR/swtpm-localca.options
EOF

[ -S "$SOCKET_PATH" ] && rm -f "$SOCKET_PATH"
[ -f "$PID_FILE" ] && rm -f "$PID_FILE"

if [ ! -e "$SWTPM_STATE_DIR/tpm2-00.permall" ]; then
  swtpm_setup \
    --tpm2 \
    --tpmstate "$SWTPM_STATE_DIR" \
    --create-ek-cert \
    --allow-signing \
    --config "$SWTPM_CONF_DIR/swtpm_setup.conf" \
    --profile-file="$PWD/swtpm-profile.json"
fi

swtpm socket \
  --tpmstate "dir=$SWTPM_STATE_DIR" \
  --ctrl "type=unixio,path=$SOCKET_PATH" \
  --pid "file=$PID_FILE" \
  --log "file=$LOG_FILE,level=20" \
  --tpm2 \
  -d

timeout=0
while [ ! -S "$SOCKET_PATH" ]; do
  if [ "$timeout" -ge 30 ]; then
    echo "'$SOCKET_PATH' timed out" >&2
    exit 1
  fi
  sleep 1
  timeout=$((timeout + 1))
done

swtpm_pid=$(cat "$PID_FILE")
echo "$swtpm_pid $SOCKET_PATH"
