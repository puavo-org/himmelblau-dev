#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3-0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

echo "config: debian start"

HOST_USER="himmelblau-demo"
HOST_PASSWORD="himmelblau"

export DEBIAN_FRONTEND=noninteractive

systemctl mask gdm3.service

echo "UUID=$(blkid -s UUID -o value /dev/sda1) /boot/efi vfat umask=0077 0 1" >/etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/sda2) / ext4 errors=remount-ro 0 1" >>/etc/fstab

echo "himmelblau-demo" >/etc/hostname
echo "127.0.0.1 localhost" >/etc/hosts
echo "127.0.1.1 himmelblau-demo" >>/etc/hosts

debconf-set-selections <<EOF
keyboard-configuration keyboard-configuration/layoutcode string en
keyboard-configuration keyboard-configuration/variant select English (US)
keyboard-configuration keyboard-configuration/model select Generic 105-key PC (intl.)
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
locales locales/default_environment_locale select en_US.UTF-8
tzdata tzdata/Areas select Europe
tzdata tzdata/Zones/Europe select Helsinki
EOF

rm -f /etc/default/locale /etc/locale.gen /etc/default/keyboard
DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-setup
DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive tzdata

useradd "$HOST_USER" -m
usermod -aG sudo "$HOST_USER"
usermod -s /bin/bash "$HOST_USER"
echo "$HOST_USER:$HOST_PASSWORD" | chpasswd

chage -d 0 "$HOST_USER"

passwd -d root
passwd -l root

apt-get -o APT::Sandbox::User=root update
apt-get -o APT::Sandbox::User=root install -y \
  bash \
  gdm3 \
  gnome-shell \
  gnome-terminal \
  grub-efi-amd64 \
  grub-efi-amd64-signed \
  krb5-user \
  linux-image-amd64 \
  qemu-guest-agent

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
update-grub

systemctl unmask gdm3.service
systemctl set-default graphical.target
systemctl enable avahi-daemon.service
systemctl enable avahi-daemon.socket
systemctl enable qemu-guest-agent.service
systemctl mask nscd.service

echo "config: debian end"

echo "config: himmelblau start"

VERSION=$(cat /tmp/himmelblau.version)
DISTRO="debian12"
ARCH="amd64"
DEB_DIR="/tmp/himmelblau_debs"

PACKAGES="himmelblau nss-himmelblau pam-himmelblau himmelblau-sso"
BASE_URL="https://github.com/himmelblau-idm/himmelblau/releases/download/$VERSION"

mkdir -p "$DEB_DIR"

for PKG in $PACKAGES; do
  FILENAME="${PKG}_${VERSION}-${DISTRO}_${ARCH}.deb"
  URL="$BASE_URL/$FILENAME"
  echo "Downloading $URL..."
  curl --fail -L -o "$DEB_DIR/$FILENAME" "$URL"
done

apt-get update
apt-get install -y "$DEB_DIR"/*.deb

rm -rf "$DEB_DIR"

mkdir -p /etc/himmelblau
cp "/tmp/himmelblau.conf" /etc/himmelblau

if ! grep -q "^passwd:.*himmelblau" /etc/nsswitch.conf; then
  sed -i '/^passwd:/ s/$/ himmelblau/' /etc/nsswitch.conf
fi
if ! grep -q "^shadow:.*himmelblau" /etc/nsswitch.conf; then
  sed -i '/^shadow:/ s/$/ himmelblau/' /etc/nsswitch.conf
fi
if ! grep -q "^group:.*himmelblau" /etc/nsswitch.conf; then
  sed -i '/^group:/ s/$/ himmelblau/' /etc/nsswitch.conf
fi

pam-auth-update --force
apt-get clean

systemctl enable himmelblaud.service
systemctl enable himmelblaud-tasks.service

echo "config: himmeblau end"
