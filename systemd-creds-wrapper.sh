#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Opinsys Oy

set -eu

SYSTEMD_CREDS_BIN="/usr/bin/systemd-creds.bin"

mode=""
if [ "$#" -gt 0 ]; then
  mode="$1"
  args="$1"
  shift
else
  args=""
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-key=*)
      key="${1#--with-key=}"
      case "$key" in
        auto|host|host+tpm2)
          args="$args --with-key=auto-initrd"
          ;;
        *)
          args="$args $1"
          ;;
      esac
      ;;
    -H)
      args="$args --with-key=auto-initrd"
      ;;
    *)
      args="$args $1"
      ;;
  esac
  shift
done

if [ "$mode" = "encrypt" ] && ! printf '%s\n' "$args" | grep -q -- '--with-key='; then
  args="$args --with-key=auto-initrd"
fi

exec "$SYSTEMD_CREDS_BIN" $args
