#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

PACKAGES='
apt-utils
avahi-daemon
bash
ca-certificates
console-setup
curl
gdm3
gnome-shell
gnome-terminal
grub-efi-amd64
grub-efi-amd64-signed
iproute2
iputils-ping
jq
krb5-user
less
linux-image-amd64
locales
lsb-release
mesa-utils
mesa-vulkan-drivers
openssh-server
qemu-guest-agent
spice-vdagent
sudo
systemd
tzdata
udhcpc
vim
zstd
'
PACKAGES=$(echo "$PACKAGES" | tr '\n' ' ')

REQUIRED_VARIABLES=(
  "ENABLE_HELLO"
  "HSM_TYPE"
  "TENANT_DOMAIN"
  "TENANT_ID"
)

for var in "${REQUIRED_VARIABLES[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "'$var' is not defined" >&2
    exit 1
  fi
done

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <output_dir>" >&2
  exit 1
fi

BUILD_DIR=$1
IMAGE_PATH="$BUILD_DIR/himmelblau-demo.qcow2"
ROOTFS_DIR="$BUILD_DIR/mnt"

OVMF_CODE="$(find /usr/share/OVMF -regex '.*/\(OVMF_CODE_4M.fd\|OVMF_CODE.fd\)' | head -1)"
echo "$OVMF_CODE"
if [ ! -f "$OVMF_CODE" ]; then
  echo "OVMF firmware blob not found." >&2
  exit 1
fi

OVMF_VARS="$(find /usr/share/OVMF -regex '.*/\(OVMF_VARS_4M.fd\|OVMF_VARS.fd\)' | head -1)"
if [ ! -f "$OVMF_VARS" ]; then
  echo "OVMF EFI variable blob not found." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

cp "$OVMF_CODE" "$BUILD_DIR/OVMF_CODE.fd"
cp "$OVMF_VARS" "$BUILD_DIR/OVMF_VARS.fd.template"

BLOCK_DEVICE=""

device_release() {
  set +e

  if mountpoint -q "$ROOTFS_DIR"; then
    sudo umount "$ROOTFS_DIR"
  fi

  if [ -n "$BLOCK_DEVICE" ]; then
    sudo qemu-nbd -d "$BLOCK_DEVICE" >/dev/null 2>&1 || true
    if command -v udevadm >/dev/null 2>&1; then
      sudo udevadm settle || true
    fi
    sleep 1
  fi
}

trap device_release EXIT INT TERM

if [ ! -d "$BUILD_DIR" ]; then
  echo "\"$BUILD_DIR\" is not a directory" >&2
  exit 1
fi

SCRIPT_DIR="${0%/*}"
if [ "$SCRIPT_DIR" = "$0" ] || [ -z "$SCRIPT_DIR" ]; then
  SCRIPT_DIR="."
fi
CONFIG_TEMPLATE="$SCRIPT_DIR/himmelblau.conf.in"

if [ ! -f "$CONFIG_TEMPLATE" ]; then
  echo "'$CONFIG_TEMPLATE' not found" >&2
  exit 1
fi

sed \
  -e "s/{{domains}}/$TENANT_DOMAIN/g" \
  -e "s/{{hsm_type}}/$HSM_TYPE/g" \
  -e "s/{{enable_hello}}/$ENABLE_HELLO/g" \
  "$CONFIG_TEMPLATE" > "$BUILD_DIR/himmelblau.conf"

qemu-img create -f qcow2 "$IMAGE_PATH" 50G

# Ensure the nbd module is available; prefer sane defaults if not yet loaded.
if [ ! -d /sys/module/nbd ]; then
  sudo modprobe nbd nbds_max=64 max_part=16 2>/dev/null || sudo modprobe nbd || true
fi

# Robust NBD acquisition: poll up to 20s, every 200ms.
acquired=0
for _ in $(seq 1 100); do
  for sysfs_dev in /sys/class/block/nbd*; do
    [ -e "$sysfs_dev" ] || continue
    block_dev="/dev/$(basename "$sysfs_dev")"

    # Skip if device shows an owning pid.
    if [ -r "$sysfs_dev/pid" ] && [ -s "$sysfs_dev/pid" ]; then
      continue
    fi

    # Prefer devices whose size is 0 (disconnected).
    size=$(cat "$sysfs_dev/size" 2>/dev/null || echo 0)
    if [ "$size" != "0" ]; then
      continue
    fi

    if sudo qemu-nbd -c "$block_dev" "$IMAGE_PATH" 2>/dev/null; then
      BLOCK_DEVICE="$block_dev"
      acquired=1
      break
    fi
  done
  if [ "$acquired" -eq 1 ]; then
    break
  fi
  sleep 0.2
done

if [ -z "$BLOCK_DEVICE" ]; then
  cur_max="$(cat /sys/module/nbd/parameters/nbds_max 2>/dev/null || echo unknown)"
  echo "Out of free network block devices after 20s timeout (nbds_max=$cur_max)." >&2
  exit 1
fi

if command -v udevadm >/dev/null 2>&1; then
  sudo udevadm settle || true
fi

sudo partprobe "$BLOCK_DEVICE"

sudo parted -s -a optimal -- "$BLOCK_DEVICE" \
  mklabel gpt \
  mkpart primary fat32 1MiB 512MiB \
  mkpart primary ext4 512MiB -0 \
  name 1 EFI \
  name 2 root \
  set 1 esp on

sudo partprobe "$BLOCK_DEVICE"

EFI_PART="${BLOCK_DEVICE}p1"
ROOT_PART="${BLOCK_DEVICE}p2"

sudo mkfs.fat -F 32 -n EFI "$EFI_PART"
sudo mkfs.ext4 -L root "$ROOT_PART"

mkdir -p "$ROOTFS_DIR"
sudo mount "$ROOT_PART" "$ROOTFS_DIR"

sudo debootstrap \
  --arch=amd64 \
  --include="$PACKAGES" \
  --components=main,contrib,non-free,non-free-firmware \
  --variant=minbase \
  bookworm "$ROOTFS_DIR" http://deb.debian.org/debian/
