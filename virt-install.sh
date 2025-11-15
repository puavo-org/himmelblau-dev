#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

if ! command -v virsh >/dev/null 2>&1; then
  echo "'virsh' not found (install 'libvirt-clients')." >&2
  exit 1
fi

if ! command -v uuidgen >/dev/null 2>&1; then
  echo "'uuidgen' not found (install 'util-linux' or 'uuid-runtime')." >&2
  exit 1
fi

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <build_dir>" >&2
  exit 1
fi

BUILD_DIR=$1

if [ ! -d "$BUILD_DIR" ]; then
  echo "'$BUILD_DIR' is not a directory" >&2
  exit 1
fi

BUILD_DIR=$(cd "$BUILD_DIR" && pwd)

IMAGE="$BUILD_DIR/himmelblau-demo.qcow2"
OVMF_CODE="$BUILD_DIR/OVMF_CODE.fd"
OVMF_VARS_TEMPLATE="$BUILD_DIR/OVMF_VARS.fd.template"
OVMF_VARS="$BUILD_DIR/OVMF_VARS.fd"
XML_TEMPLATE="himmelblau-demo.xml.in"
XML_PATH="$BUILD_DIR/himmelblau-demo.xml"
LIBVIRT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///session}"

if [ ! -f "$IMAGE" ]; then
  echo "'$IMAGE' not found; run 'make build' first." >&2
  exit 1
fi

if ! command -v guestfish >/dev/null 2>&1; then
  echo "'guestfish' not found (install 'libguestfs-tools')." >&2
  exit 1
fi

export LIBGUESTFS_BACKEND="${LIBGUESTFS_BACKEND:-libvirt}"

guestfish -a "$IMAGE" <<'EOF'
set-network true
run

mount /dev/sda2 /
mkdir /boot/efi
mount /dev/sda1 /boot/efi

sh "if [ ! -s /etc/machine-id ]; then systemd-machine-id-setup; fi"
# sh "mkdir -p /var/lib/systemd && /usr/bin/systemd-creds setup --with-key=host"


umount /boot/efi
umount /
EOF

if [ ! -f "$OVMF_CODE" ]; then
  echo "'$OVMF_CODE' not found; run 'make build' first." >&2
  exit 1
fi

if [ ! -f "$OVMF_VARS_TEMPLATE" ]; then
  echo "'$OVMF_VARS_TEMPLATE' not found; run 'make build' first." >&2
  exit 1
fi

if [ ! -f "$XML_TEMPLATE" ]; then
  echo "'$XML_TEMPLATE' not found." >&2
  exit 1
fi

if [ ! -f "$OVMF_VARS" ]; then
  cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
fi

UUID=$(uuidgen)

sed -e "s|{{BUILD_DIR}}|$BUILD_DIR|g" \
    -e "s|{{UUID}}|$UUID|g" \
    "$XML_TEMPLATE" > "$XML_PATH"

virsh -c "$LIBVIRT_URI" define "$XML_PATH" >/dev/null
echo "Domain defined from $XML_PATH"
