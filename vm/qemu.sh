#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

if [ $# -ne 4 ]; then
  echo "Usage: $(basename "$0") <json_config> <output_dir> <network_mode> <swtpm_socket>" >&2
  exit 1
fi

CONFIG_FILE="$1"
BUILD_DIR="$2"
NETWORK_MODE="$3"
SWTPM_SOCK="$4"

if ! command -v jq >/dev/null 2>&1; then
  echo "'jq' not found" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found at '$CONFIG_FILE'" >&2
  exit 1
fi

QEMU_BINARY="qemu-system-x86_64"
QEMU_ARGS=()

args_list=$(jq -r '
  {
    "memory": "m"
  } as $map |
  .args | to_entries[] |
  ($map[.key] // .key) as $flag |
  if .value == true then
    "-\($flag)"
  else
    "-\($flag)", .value
  end' "$CONFIG_FILE")
while IFS= read -r arg; do
  QEMU_ARGS+=("$arg")
done <<EOF
$args_list
EOF

net_list=$(jq -r --arg mode "$NETWORK_MODE" '
  .networking[$mode][] | to_entries[] | "-\(.key)", .value
  ' "$CONFIG_FILE")
while IFS= read -r arg; do
  QEMU_ARGS+=("$arg")
done <<EOF
$net_list
EOF

if [ "$(jq -r '.tpm.enabled' "$CONFIG_FILE")" = "true" ]; then
  QEMU_ARGS+=(-chardev "socket,id=chrtpm,path=$SWTPM_SOCK")
  tpm_list=$(jq -r '
    .tpm | del(.enabled) | to_entries[] | "-\(.key)", .value
    ' "$CONFIG_FILE")
  while IFS= read -r arg; do
    QEMU_ARGS+=("$arg")
  done <<EOF
$tpm_list
EOF
fi

drive_list=$(jq -r --arg outdir "$BUILD_DIR" '
  .drives[] |
  (
    to_entries |
    map(
      if .key == "file" then
        .key + "=" + $outdir + "/" + .value
      else
        .key + "=" + .value
      end
    ) | join(",")
  )
' "$CONFIG_FILE")
while IFS= read -r drive_string; do
  QEMU_ARGS+=(-drive "$drive_string")
done <<EOF
$drive_list
EOF

exec "$QEMU_BINARY" "${QEMU_ARGS[@]}"