#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) Opinsys Oy 2025

set -eu

echo "DEBIAN"

HOST_USER="himmelblau"
HOST_PASSWORD="himmelblau"

export DEBIAN_FRONTEND=noninteractive

systemctl mask gdm3.service

# /etc/fstab
{
  echo "UUID=$(blkid -s UUID -o value /dev/sda1) /boot/efi vfat umask=0077 0 1"
  echo "UUID=$(blkid -s UUID -o value /dev/sda2) / ext4 errors=remount-ro 0 1"
} > /etc/fstab

# /etc/hosts
{
  echo "127.0.0.1 localhost"
  echo "127.0.1.1 himmelblau-demo"
} > /etc/hosts

# /etc/hostname
echo "himmelblau-demo" >/etc/hostname

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

passwd -d root
passwd -l root

apt-get -o APT::Sandbox::User=root update

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
update-grub

systemctl unmask gdm3.service
systemctl set-default graphical.target
systemctl enable avahi-daemon.service
systemctl enable avahi-daemon.socket
systemctl mask nscd.service

echo "HIMMELBLAU"

# Use a distinct var name to avoid collision with os-release's VERSION
HB_VERSION=$(cat /tmp/himmelblau.version)

# Detect distro codename for repo path (e.g., debian12)
DISTRO="debian12"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" = "debian" ] && [ -n "${VERSION_ID:-}" ]; then
    DISTRO="debian${VERSION_ID%%.*}"
  fi
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
DEB_DIR="/tmp/himmelblau_debs"
mkdir -p "$DEB_DIR"

# Channel/filename normalization:
#   - directory uses the tag (e.g., nightly/2.0.0-beta/)
#   - files use the numeric version (e.g., *_2.0.0-debian12_amd64.deb)
if [[ "$HB_VERSION" == *-* ]]; then
  CHANNEL="nightly"
else
  CHANNEL="stable"
fi
NUMVER="${HB_VERSION%%-*}"
BASE_URL="https://packages.himmelblau-idm.org/$CHANNEL/$HB_VERSION/deb/$DISTRO"

CORE_PACKAGES="himmelblau nss-himmelblau pam-himmelblau himmelblau-sso"
OPT_PACKAGES="himmelblau-qr-greeter himmelblau-sshd-config o365"

download_pkg() {
  pkg="$1"
  file="${pkg}_${NUMVER}-${DISTRO}_${ARCH}.deb"
  url="$BASE_URL/$file"
  echo "Downloading $url..."
  curl --fail -L -o "$DEB_DIR/$file" "$url"
}

# Fetch core packages (required)
for PKG in $CORE_PACKAGES; do
  if ! download_pkg "$PKG"; then
    echo "Error: failed to download required package '$PKG' from '$BASE_URL'." >&2
    exit 1
  fi
done

# Fetch optional packages (best-effort)
for PKG in $OPT_PACKAGES; do
  if ! download_pkg "$PKG"; then
    echo "Optional package '$PKG' not found at repo; continuing."
  fi
done

apt-get -o APT::Sandbox::User=root update
apt-get -o APT::Sandbox::User=root install -y "$DEB_DIR"/*.deb

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

echo "config: himmelblau end"
