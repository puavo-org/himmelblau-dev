#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

echo "config: init start"

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <output_dir>" >&2
  exit 1
fi

BUILD_DIR=$1

BUILD_IMAGE_PATH="$BUILD_DIR/himmelblau-demo.qcow2"

if ! command -v guestfish >/dev/null 2>&1; then
  echo "'guestfish' not found" >&2
  exit 1
fi

guestfish -a "$BUILD_IMAGE_PATH" <<EOF
set-network true
run

mount /dev/sda2 /
mkdir /boot/efi
mount /dev/sda1 /boot/efi

copy-in "$BUILD_DIR/himmelblau.conf" /tmp
copy-in "install-debian.sh" /tmp
copy-in "himmelblau.version" /tmp

chmod 0700 /tmp/install-debian.sh

sh "/tmp/install-debian.sh"

umount /boot/efi
umount /
EOF

echo "config: init end"
