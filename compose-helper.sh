#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Opinsys Oy

set -eu

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
ROOTFS_DIR="/rootfs"
OUTPUT_IMG="$WORKSPACE_DIR/himmelblau-demo.qcow2"

REQUIRED_VARS="TENANT_ID TENANT_DOMAIN HSM_TYPE ENABLE_HELLO"
for var in $REQUIRED_VARS; do
  if [ -z "${!var:-}" ]; then
    echo "'$var' is not set" >&2
    exit 1
  fi
done

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends \
  dosfstools mtools fdisk qemu-utils ca-certificates curl xz-utils \
  gpg gpg-agent dpkg-dev mmdebstrap python3

# Some maintainer scripts expect this group to exist on the *build host*
if ! getent group messagebus >/dev/null 2>&1; then
  printf 'messagebus:x:201:\n' >> /etc/group
fi

# No-op shims for tools that maintainer scripts may try to call on the *host*
cat > /tmp/noop_mock <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x /tmp/noop_mock

TOOLS="systemctl journalctl systemd-sysusers systemd-tmpfiles udevadm systemd-machine-id-setup systemd-hwdb"

for tool in $TOOLS; do
  if [ ! -e "/bin/$tool" ]; then
    cp /tmp/noop_mock "/bin/$tool"
  fi
  if [ ! -e "/usr/bin/$tool" ]; then
    cp /tmp/noop_mock "/usr/bin/$tool"
  fi
done

rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

# Desktop + GNOME + Xorg + virgl-friendly graphics stack
PACKAGES="apt-utils,avahi-daemon,bash,ca-certificates,console-setup,curl,dbus,dbus-x11,dmz-cursor-theme,fonts-dejavu,gdm3,gnome-session,gnome-shell,gnome-shell-extensions,gnome-control-center,gnome-terminal,gnome-system-monitor,gnome-keyring,gnome-settings-daemon,gnome-backgrounds,gnome-themes-extra,nautilus,adwaita-icon-theme,mutter,network-manager,network-manager-gnome,xorg,xserver-xorg-core,xserver-xorg,xserver-xorg-video-all,x11-xserver-utils,x11-utils,xwayland,grub-efi-amd64-signed,grub-efi-amd64,shim-signed,iproute2,iputils-ping,jq,krb5-user,less,locales,lsb-release,mesa-utils,mesa-vulkan-drivers,libgl1-mesa-dri,libegl-mesa0,libgles2,openssh-server,qemu-guest-agent,spice-vdagent,sudo,systemd,systemd-sysv,polkitd,pkexec,tzdata,vim,zstd,linux-image-amd64,libtss2-esys-3.0.2-0t64,libtss2-tctildr0t64,libnss-mdns"

mmdebstrap \
  --variant=apt \
  --arch=amd64 \
  --include="$PACKAGES" \
  trixie \
  "$ROOTFS_DIR" \
  http://deb.debian.org/debian/

mv "$ROOTFS_DIR/usr/bin/systemd-creds" "$ROOTFS_DIR/usr/bin/systemd-creds.bin"
cp "$WORKSPACE_DIR/systemd-creds-wrapper.sh" "$ROOTFS_DIR/usr/bin/systemd-creds"
chmod +x "$ROOTFS_DIR/usr/bin/systemd-creds"

echo "himmelblau-demo" > "$ROOTFS_DIR/etc/hostname"
cat > "$ROOTFS_DIR/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 himmelblau-demo
EOF

cat > "$ROOTFS_DIR/etc/fstab" <<EOF
LABEL=root / ext4 errors=remount-ro 0 1
LABEL=EFI  /boot/efi vfat umask=0077 0 1
EOF

# Local user
PASS_HASH=$(python3 -c 'import crypt; print(crypt.crypt("himmelblau", crypt.mksalt(crypt.METHOD_SHA512)))')
echo "himmelblau:x:1000:1000:,,,:/home/himmelblau:/bin/bash" >> "$ROOTFS_DIR/etc/passwd"
echo "himmelblau:$PASS_HASH:19742:0:99999:7:::" >> "$ROOTFS_DIR/etc/shadow"
echo "himmelblau:x:1000:" >> "$ROOTFS_DIR/etc/group"
mkdir -p "$ROOTFS_DIR/home/himmelblau"
chown 1000:1000 "$ROOTFS_DIR/home/himmelblau"

# Sudo access
if grep -q '^sudo:.*:$' "$ROOTFS_DIR/etc/group"; then
  sed -i '/^sudo:/ s/$/himmelblau/' "$ROOTFS_DIR/etc/group"
else
  sed -i '/^sudo:/ s/$/,himmelblau/' "$ROOTFS_DIR/etc/group"
fi

# Ensure messagebus group exists inside the guest too
if [ -f "$ROOTFS_DIR/etc/group" ] && ! grep -q '^messagebus:' "$ROOTFS_DIR/etc/group"; then
  printf 'messagebus:x:201:\n' >> "$ROOTFS_DIR/etc/group"
fi

# Root password
ROOT_PASS_HASH=$(python3 -c 'import crypt; print(crypt.crypt("root", crypt.mksalt(crypt.METHOD_SHA512)))')
sed -i "s|^root:[^:]*:|root:$ROOT_PASS_HASH:|" "$ROOTFS_DIR/etc/shadow"

# Timezone
echo "Europe/Helsinki" > "$ROOTFS_DIR/etc/timezone"
rm -f "$ROOTFS_DIR/etc/localtime"
ln -s /usr/share/zoneinfo/Europe/Helsinki "$ROOTFS_DIR/etc/localtime"

# Kernel cmdline – keep tty0 *and* serial console
GRUB_DEFAULT="$ROOTFS_DIR/etc/default/grub"
if [ -f "$GRUB_DEFAULT" ]; then
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=tty0 console=ttyS0,115200"/' "$GRUB_DEFAULT"
else
  echo "Warning: $GRUB_DEFAULT not found; skipping GRUB_CMDLINE_LINUX_DEFAULT update" >&2
fi

# Himmelblau packages
HB_VERSION=$(cat "$WORKSPACE_DIR/himmelblau.version")
case "$HB_VERSION" in
  *-*) CHANNEL="nightly" ;;
  *) CHANNEL="stable" ;;
esac
BASE_URL="https://packages.himmelblau-idm.org/$CHANNEL/$HB_VERSION/deb/debian13"

mkdir -p "$ROOTFS_DIR/tmp/hb_debs"
CORE_PACKAGES="himmelblau nss-himmelblau pam-himmelblau himmelblau-sso"

for PKG in $CORE_PACKAGES; do
  file="${PKG}_${HB_VERSION%%-*}-debian13_amd64.deb"
  curl -fsSL -o "$ROOTFS_DIR/tmp/hb_debs/$file" "$BASE_URL/$file"
done

# Install Himmelblau packages inside the guest rootfs so maintainer scripts
# run in a normal Debian 13 environment.
chroot "$ROOTFS_DIR" sh -c 'dpkg -i /tmp/hb_debs/*.deb'

rm -rf "$ROOTFS_DIR/tmp/hb_debs"

# Basic Himmelblau config
mkdir -p "$ROOTFS_DIR/etc/himmelblau"
cat > "$ROOTFS_DIR/etc/himmelblau/himmelblau.conf" <<EOF
[global]
debug = true
domains = ${TENANT_DOMAIN}
app_id = ${TENANT_ID}
home_alias = CN
home_attr = CN
id_attr_map = name
pam_allow_groups =
use_etc_skel = true
local_groups = users
hsm_type = ${HSM_TYPE}
enable_hello = ${ENABLE_HELLO}
EOF

# NSS modules
sed -i '/^passwd:/ s/$/ himmelblau/' "$ROOTFS_DIR/etc/nsswitch.conf"
sed -i '/^shadow:/ s/$/ himmelblau/' "$ROOTFS_DIR/etc/nsswitch.conf"
sed -i '/^group:/ s/$/ himmelblau/' "$ROOTFS_DIR/etc/nsswitch.conf"

# Enable Himmelblau services
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/himmelblaud.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/himmelblaud.service"
ln -sf /lib/systemd/system/himmelblaud-tasks.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/himmelblaud-tasks.service"

# Enable NetworkManager explicitly (in case maint scripts couldn't)
ln -sf /lib/systemd/system/NetworkManager.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# Boot to graphical target with GDM
mkdir -p "$ROOTFS_DIR/etc/systemd/system"
ln -sf /lib/systemd/system/graphical.target "$ROOTFS_DIR/etc/systemd/system/default.target"
ln -sf /lib/systemd/system/gdm3.service "$ROOTFS_DIR/etc/systemd/system/display-manager.service"

mkdir -p "$ROOTFS_DIR/etc/systemd/system/graphical.target.wants"
ln -sf /lib/systemd/system/gdm3.service "$ROOTFS_DIR/etc/systemd/system/graphical.target.wants/gdm3.service"

# Figure out kernel/initrd names
kernel=
if ls "$ROOTFS_DIR"/boot/vmlinuz-* >/dev/null 2>&1; then
  kernel=$(basename "$(ls "$ROOTFS_DIR"/boot/vmlinuz-* 2>/dev/null | sort | tail -n 1)")
fi

initrd=
if [ -n "${kernel:-}" ] && [ -f "$ROOTFS_DIR/boot/initrd.img-${kernel#vmlinuz-}" ]; then
  initrd="initrd.img-${kernel#vmlinuz-}"
elif ls "$ROOTFS_DIR"/boot/initrd.img-* >/dev/null 2>&1; then
  initrd=$(basename "$(ls "$ROOTFS_DIR"/boot/initrd.img-* 2>/dev/null | sort | tail -n 1)")
fi

# Minimal GRUB config – boots directly into our Debian install
if [ -n "${kernel:-}" ] && [ -n "${initrd:-}" ]; then
  mkdir -p "$ROOTFS_DIR/boot/grub"
  cat > "$ROOTFS_DIR/boot/grub/grub.cfg" <<EOF
search --label root --set=root
set default=0
set timeout=5

menuentry 'Debian Himmelblau Demo' {
    linux /boot/$kernel root=LABEL=root ro console=tty0 console=ttyS0,115200
    initrd /boot/$initrd
}
EOF
fi

# Disk layout: 512M EFI + rest root, with labels
IMG_SIZE="50G"
EFI_SIZE_MB=512

truncate -s "$IMG_SIZE" disk.raw

sfdisk disk.raw <<EOF
label: gpt
unit: sectors
first-lba: 2048

start=2048, size=$((EFI_SIZE_MB * 2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
start=$((2048 + EFI_SIZE_MB * 2048)), size=+, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"
EOF

dd if=/dev/zero of=efi.img bs=1M count="$EFI_SIZE_MB"
mkfs.vfat -n "EFI" efi.img

mmd -i efi.img ::/EFI
mmd -i efi.img ::/EFI/BOOT
mmd -i efi.img ::/EFI/debian

mcopy -i efi.img "$ROOTFS_DIR/usr/lib/shim/shimx64.efi.signed" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i efi.img "$ROOTFS_DIR/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ::/EFI/BOOT/grubx64.efi

cat > grub.cfg.stub <<'EOF'
search --label root --set=root
set prefix=($root)/boot/grub
configfile $prefix/grub.cfg
EOF
mcopy -i efi.img grub.cfg.stub ::/EFI/debian/grub.cfg

mkfs.ext4 -q -L "root" -d "$ROOTFS_DIR" -E root_owner=0:0 root.img "$((48 * 1024))M"

dd if=efi.img of=disk.raw bs=512 seek=2048 conv=notrunc status=none
dd if=root.img of=disk.raw bs=512 seek=$((2048 + EFI_SIZE_MB * 2048)) conv=notrunc status=none

qemu-img convert -f raw -O qcow2 disk.raw "$OUTPUT_IMG"
