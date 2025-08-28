#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

OVMF_CODE_SRC="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS_SRC="/usr/share/OVMF/OVMF_VARS.fd"

source "bootstrap/settings.sh"

for cmd in curl qemu-img parted mkfs.fat mkfs.ext4 debootstrap getopt jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "'$cmd' not found" >&2
    exit 1
  fi
done

HIMMELBLAU_UPDATE=false
CONFIG_FILE=""
if ! opts=$(getopt -o uc: --long update,config: -n "$(basename "$0")" -- "$@"); then
  echo "Invalid options" >&2
  exit 1
fi
eval set -- "$opts"
while true; do
  case "$1" in
  -u | --update)
    HIMMELBLAU_UPDATE=true
    shift
    ;;
  -c | --config)
    CONFIG_FILE="$2"
    shift 2
    ;;
  --)
    shift
    break
    ;;
  esac
done

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") [-u|--update] [--config <file>] <output>" >&2
  exit 1
fi

OUTPUT=$1
mkdir -p "$OUTPUT"

HIMMELBLAU_CONF="$OUTPUT/himmelblau.conf"
IMAGE="$OUTPUT/himmelblau-demo.qcow2"

settings_load "$CONFIG_FILE"
settings_check

if [ "$HIMMELBLAU_UPDATE" = "true" ]; then
  url="https://api.github.com/repos/himmelblau-idm/himmelblau/releases/latest"
  version=$(curl -sSf "$url" | jq -r '.tag_name')

  if [ -z "$version" ]; then
    echo "Fetching Himmelblau version failed" >&2
    echo "Skipping Himmelblau version update" >&2
    exit 1
  fi
  echo "$version" >"himmelblau.version"
fi

teardown() {
  sudo umount /mnt 2>/dev/null || true
  sudo qemu-nbd -d /dev/nbd0 2>/dev/null || true
}

trap teardown EXIT INT TERM

if [ ! -d "$OUTPUT" ]; then
  echo "\"$OUTPUT\" is not a directory" >&2
  exit 1
fi

settings_generate "$HIMMELBLAU_CONF"

if [ ! -f "$OVMF_CODE_SRC" ] || [ ! -f "$OVMF_VARS_SRC" ]; then
  echo "OVMF firmware files not found." >&2
  exit 1
fi

cp "$OVMF_CODE_SRC" "$OUTPUT/OVMF_CODE.fd"
cp "$OVMF_VARS_SRC" "$OUTPUT/OVMF_VARS.fd.template"

qemu-img create -f qcow2 "$IMAGE" 50G

sudo qemu-nbd -c /dev/nbd0 "$IMAGE"

sudo parted -s -a optimal -- /dev/nbd0 \
  mklabel gpt \
  mkpart primary fat32 1MiB 512MiB \
  mkpart primary ext4 512MiB -0 \
  name 1 EFI \
  name 2 root \
  set 1 esp on

sudo partprobe /dev/nbd0

sudo mkfs.fat -F 32 -n EFI /dev/nbd0p1
sudo mkfs.ext4 -L root /dev/nbd0p2

sudo mount /dev/nbd0p2 /mnt

sudo debootstrap \
  --arch=amd64 \
  --include="apt-utils,console-setup,curl,iproute2,iputils-ping,jq,less,locales,lsb-release,sudo,systemd,systemd-sysv,tzdata,udhcpc,zstd,ca-certificates" \
  --components=main,contrib,non-free,non-free-firmware \
  --variant=minbase \
  bookworm /mnt http://httpredir.debian.org/debian/

sudo umount /mnt
sudo qemu-nbd -d /dev/nbd0
