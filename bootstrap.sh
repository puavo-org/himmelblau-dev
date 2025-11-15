#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Opinsys Oy

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <build_dir>" >&2
  exit 1
fi

BUILD_DIR=$1

mkdir -p "$BUILD_DIR"

CODE_OUT="$BUILD_DIR/OVMF_CODE.fd"
VARS_TEMPLATE_OUT="$BUILD_DIR/OVMF_VARS.fd.template"

CANDIDATES="
/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd
/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd
/usr/share/qemu/OVMF_CODE.fd:/usr/share/qemu/OVMF_VARS.fd
/usr/share/qemu/OVMF_CODE.secboot.fd:/usr/share/qemu/OVMF_VARS.secboot.fd
/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd
/usr/share/edk2-ovmf/x64/OVMF_CODE.fd:/usr/share/edk2-ovmf/x64/OVMF_VARS.fd
/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd
"

CODE_SRC=
VARS_SRC=

for pair in $CANDIDATES; do
  CODE=${pair%%:*}
  VARS=${pair#*:}
  if [ -f "$CODE" ] && [ -f "$VARS" ]; then
    CODE_SRC="$CODE"
    VARS_SRC="$VARS"
    break
  fi
done

if [ -z "$CODE_SRC" ] || [ -z "$VARS_SRC" ]; then
  echo "Error: could not locate OVMF firmware (code + vars) on this system." >&2
  echo "Install your distribution's OVMF/edk2-ovmf package and retry." >&2
  exit 1
fi

cp "$CODE_SRC" "$CODE_OUT"
cp "$VARS_SRC" "$VARS_TEMPLATE_OUT"
