#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

echo "config: init start"

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <output_dir>" >&2
  exit 1
fi

OUTPUT=$1

HIMMELBLAU_CONF="$OUTPUT/himmelblau.conf"
IMAGE="$OUTPUT/himmelblau-demo.qcow2"

if ! command -v guestfish >/dev/null 2>&1; then
  echo "'guestfish' not found" >&2
  exit 1
fi

guestfish -a "$IMAGE" <<EOF
set-network true
run

mount /dev/sda2 /
mkdir /boot/efi
mount /dev/sda1 /boot/efi

copy-in "$HIMMELBLAU_CONF" /tmp
copy-in "config/debian.sh" /tmp
copy-in "himmelblau.version" /tmp

chmod 0700 /tmp/debian.sh

sh "/tmp/debian.sh"

umount /boot/efi
umount /
EOF

echo "config: init end"
